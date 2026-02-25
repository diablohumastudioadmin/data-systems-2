@tool
class_name DatabaseManager
extends Node

## Single orchestrator for the database system.
## Registered as an autoload by the plugin. Works in editor and at runtime.
## The filesystem IS the database:
##   - Schema = table_structures/*.gd files
##   - Data = instances/<table>/*.tres files
##   - Constraints = REQUIRED_FIELDS + FK_FIELDS consts inside .gd scripts

signal data_changed(table_name: String)
signal tables_changed()

## Base DataItem fields to exclude from table field reflection
const _BASE_FIELD_NAMES: Array[String] = [
	"resource_local_to_scene", "resource_path", "resource_name", "script",
	"name", "id"
]

const DEFAULT_BASE_PATH := "res://database/res/"

var base_path: String = DEFAULT_BASE_PATH
var structures_path: String:
	get: return base_path.path_join("table_structures/")
var instances_path: String:
	get: return base_path.path_join("instances/")

var _storage: StorageAdapter
## {table_name: Array[DataItem]} — populated lazily on first access
var _instance_cache: Dictionary = {}
## {table_name: {id_int: DataItem}} — for fast ID lookups
var _id_cache: Dictionary = {}
## Cached list of table names from filesystem
var _table_names_cache: Array[String] = []
var _table_names_dirty: bool = true


func _init() -> void:
	_storage = ResourceStorageAdapter.new()


func _ready() -> void:
	reload()


# --- Core -------------------------------------------------------------------

func reload() -> void:
	if MigrationHelper.needs_migration(base_path):
		MigrationHelper.migrate_v1_to_v2(base_path, _storage)
	_instance_cache.clear()
	_id_cache.clear()
	_table_names_dirty = true


# --- Table Management --------------------------------------------------------

func get_table_names() -> Array[String]:
	if _table_names_dirty:
		_table_names_cache = _scan_table_names()
		_table_names_dirty = false
	return _table_names_cache


func has_table(table_name: String) -> bool:
	return table_name in get_table_names()


## Read schema from the generated .gd script via reflection.
## Only returns @export fields declared in the generated subclass.
## Returns: [{name, type, default, hint, hint_string, class_name}, ...]
func get_table_fields(table_name: String) -> Array[Dictionary]:
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	var script: GDScript = _load_fresh_script(script_path)
	if script == null:
		return []

	var temp = script.new()
	var fields: Array[Dictionary] = []
	for p in script.get_script_property_list():
		if not (p.usage & PROPERTY_USAGE_EDITOR):
			continue
		if p.name in _BASE_FIELD_NAMES:
			continue
		fields.append({
			"name": p.name,
			"type": p.type,
			"default": temp.get(p.name),
			"hint": p.get("hint", PROPERTY_HINT_NONE),
			"hint_string": p.get("hint_string", ""),
			"class_name": p.get("class_name", "")
		})
	return fields


func table_has_field(table_name: String, field_name: String) -> bool:
	var fields = get_table_fields(table_name)
	for f in fields:
		if f.name == field_name:
			return true
	return false


## Get constraints from the _required_fields and _fk_fields vars set in _init().
## Parses the _init() assignments from source text (robust even when the script
## can't compile due to missing FK target classes).
## Returns: {field_name: {required: bool, foreign_key: String}}
func get_field_constraints(table_name: String) -> Dictionary:
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	if not FileAccess.file_exists(script_path):
		return {}

	var source := FileAccess.get_file_as_string(script_path)
	if source.is_empty():
		return {}

	var required: Array[String] = []
	var fk: Dictionary = {}

	for line in source.split("\n"):
		var stripped := line.strip_edges()
		# Parse: _required_fields = ["a", "b"]
		if stripped.begins_with("_required_fields = ["):
			var bracket_start := stripped.find("[")
			var bracket_end := stripped.rfind("]")
			if bracket_start >= 0 and bracket_end > bracket_start:
				var inner := stripped.substr(bracket_start + 1, bracket_end - bracket_start - 1)
				for part in inner.split(","):
					var val := part.strip_edges().trim_prefix('"').trim_suffix('"')
					if not val.is_empty():
						required.append(val)
		# Parse: _fk_fields = {"a": "B", "c": "D"}
		elif stripped.begins_with("_fk_fields = {"):
			var brace_start := stripped.find("{")
			var brace_end := stripped.rfind("}")
			if brace_start >= 0 and brace_end > brace_start:
				var inner := stripped.substr(brace_start + 1, brace_end - brace_start - 1)
				for part in inner.split(","):
					var kv := part.split(":")
					if kv.size() == 2:
						var k := kv[0].strip_edges().trim_prefix('"').trim_suffix('"')
						var v := kv[1].strip_edges().trim_prefix('"').trim_suffix('"')
						fk[k] = v

	var result: Dictionary = {}
	for field_name in required:
		if not result.has(field_name):
			result[field_name] = {}
		result[field_name]["required"] = true
	for field_name in fk:
		if not result.has(field_name):
			result[field_name] = {}
		result[field_name]["foreign_key"] = fk[field_name]
	return result


## Add a new table (generates .gd file + creates instances directory)
func add_table(table_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	if has_table(table_name):
		push_warning("Table already exists: %s" % table_name)
		return false

	if not parent_table.is_empty() and _would_create_cycle(table_name, parent_table):
		push_warning("Cannot set parent '%s': would create circular inheritance" % parent_table)
		return false

	ResourceGenerator.generate_resource_class(
		table_name, fields, structures_path, constraints, parent_table)

	# Create the instances directory for this table
	var inst_dir := instances_path.path_join(table_name.to_lower())
	DirAccess.make_dir_recursive_absolute(inst_dir)

	_table_names_dirty = true
	_scan_filesystem()
	tables_changed.emit()
	return true


## Update an existing table (regenerates .gd file)
func update_table(table_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	if not has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	if not parent_table.is_empty() and _would_create_cycle(table_name, parent_table):
		push_warning("Cannot set parent '%s': would create circular inheritance" % parent_table)
		return false

	ResourceGenerator.generate_resource_class(
		table_name, fields, structures_path, constraints, parent_table)

	# Reload the script in-place on the EXISTING cached GDScript object.
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	var cached_script: GDScript = load(script_path) as GDScript
	if cached_script:
		cached_script.source_code = FileAccess.get_file_as_string(script_path)
		cached_script.reload(true)

	# Invalidate instance cache so fresh instances pick up schema changes
	_instance_cache.erase(table_name)
	_id_cache.erase(table_name)

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(script_path)
	_scan_filesystem()
	tables_changed.emit()
	return true


## Rename a table and update its schema fields in one operation.
func rename_table(old_name: String, new_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	if not has_table(old_name):
		push_warning("Table not found: %s" % old_name)
		return false
	if has_table(new_name):
		push_warning("Table already exists: %s" % new_name)
		return false

	# Load existing instances and snapshot their property values
	var items: Array[DataItem] = get_data_items(old_name)
	var snapshots: Array[Dictionary] = []
	for item in items:
		var snap := {"id": item.id, "name": item.name}
		var old_script: GDScript = item.get_script()
		if old_script:
			for p in old_script.get_script_property_list():
				if p.usage & PROPERTY_USAGE_EDITOR:
					snap[p.name] = item.get(p.name)
		snapshots.append(snap)

	# Generate new .gd at the new path
	ResourceGenerator.generate_resource_class(
		new_name, fields, structures_path, constraints, parent_table)

	# Load the new script, swap every instance, restore values, save to new dir
	var new_script_path := structures_path.path_join("%s.gd" % new_name.to_lower())
	var new_script = ResourceLoader.load(
		new_script_path, "", ResourceLoader.CACHE_MODE_REUSE) as GDScript
	if new_script:
		for i in range(items.size()):
			var item := items[i]
			item.set_script(new_script)
			for key in snapshots[i]:
				item.set(key, snapshots[i][key])
			_storage.save_instance(item, new_name, base_path)

	# Delete old instances directory
	_storage.delete_table_instances_dir(old_name, base_path)

	# Update children that referenced the old name + regenerate their scripts
	for child_name in get_child_tables(old_name):
		_regenerate_child_script_for_rename(child_name, new_name)

	# Remove old .gd
	ResourceGenerator.delete_resource_class(old_name, structures_path)

	# Update caches
	_instance_cache.erase(old_name)
	_id_cache.erase(old_name)
	_table_names_dirty = true

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(new_script_path)
	_scan_filesystem()
	tables_changed.emit()
	return true


## Remove a table (deletes .gd file + instances directory)
func remove_table(table_name: String) -> bool:
	if not has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	var children: Array[String] = get_child_tables(table_name)
	if not children.is_empty():
		push_warning("Cannot delete '%s': has child tables: %s" % [
			table_name, ", ".join(children)])
		return false

	ResourceGenerator.delete_resource_class(table_name, structures_path)
	_storage.delete_table_instances_dir(table_name, base_path)
	_instance_cache.erase(table_name)
	_id_cache.erase(table_name)
	_table_names_dirty = true

	_scan_filesystem()
	tables_changed.emit()
	return true


# --- Instance Management -----------------------------------------------------

## Get all instances for a table (lazy-loaded from disk on first call)
func get_data_items(table_name: String) -> Array[DataItem]:
	if not _instance_cache.has(table_name):
		_load_table_instances(table_name)
	var items: Array[DataItem] = []
	items.assign(_instance_cache.get(table_name, []))
	return items


## Get a specific instance by its stable ID
func get_by_id(table_name: String, id: int) -> DataItem:
	if not _id_cache.has(table_name):
		_load_table_instances(table_name)
	var cache: Dictionary = _id_cache.get(table_name, {})
	return cache.get(id, null)


## Add a new instance with a required name and a unique ID
func add_instance(table_name: String, instance_name: String) -> DataItem:
	if instance_name.strip_edges().is_empty():
		push_error("Instance name cannot be empty")
		return null

	if not has_table(table_name):
		push_error("Table not found: %s" % table_name)
		return null

	var item: DataItem = _create_data_item(table_name)
	if item == null:
		return null

	item.name = instance_name.strip_edges()
	item.id = ResourceUID.create_id()

	# Ensure cache is loaded BEFORE saving (so lazy-load doesn't pick up the new file)
	_ensure_table_loaded(table_name)

	# Save to individual .tres file
	_storage.save_instance(item, table_name, base_path)

	# Update caches
	_instance_cache[table_name].append(item)
	_cache_item(table_name, item)

	_request_scan()
	data_changed.emit(table_name)
	return item


## Remove an instance by its stable ID (not array index)
func remove_instance(table_name: String, id: int) -> bool:
	var item: DataItem = get_by_id(table_name, id)
	if item == null:
		return false

	_storage.delete_instance(item, table_name, base_path)

	# Update caches
	if _instance_cache.has(table_name):
		var items: Array = _instance_cache[table_name]
		for i in range(items.size()):
			if items[i].id == id:
				items.remove_at(i)
				break
	_uncache_item(table_name, id)

	_request_scan()
	data_changed.emit(table_name)
	return true


## Save all instances for a table (re-saves each .tres file)
func save_instances(table_name: String) -> Error:
	var items: Array[DataItem] = get_data_items(table_name)
	var last_err := OK
	for item in items:
		var err := _storage.save_instance(item, table_name, base_path)
		if err != OK:
			last_err = err
	return last_err


## Reload instances from disk (invalidates cache)
func load_instances(table_name: String) -> void:
	_instance_cache.erase(table_name)
	_id_cache.erase(table_name)


## Delete all instances for a table
func clear_instances(table_name: String) -> void:
	_storage.delete_table_instances_dir(table_name, base_path)
	# Recreate the empty directory
	var inst_dir := instances_path.path_join(table_name.to_lower())
	DirAccess.make_dir_recursive_absolute(inst_dir)
	_instance_cache[table_name] = []
	_id_cache[table_name] = {}
	_request_scan()
	data_changed.emit(table_name)


func get_instance_count(table_name: String) -> int:
	return get_data_items(table_name).size()


# --- ID Cache ----------------------------------------------------------------

func _load_table_instances(table_name: String) -> void:
	var items: Array[DataItem] = _storage.load_instances(table_name, base_path)
	_instance_cache[table_name] = items
	_rebuild_table_id_cache(table_name)


func _ensure_table_loaded(table_name: String) -> void:
	if not _instance_cache.has(table_name):
		_load_table_instances(table_name)


func _rebuild_table_id_cache(table_name: String) -> void:
	var items: Array = _instance_cache.get(table_name, [])
	var cache := {}
	for item in items:
		if item.id >= 0:
			cache[item.id] = item
	_id_cache[table_name] = cache


func _cache_item(table_name: String, item: DataItem) -> void:
	if not _id_cache.has(table_name):
		_id_cache[table_name] = {}
	if item.id >= 0:
		_id_cache[table_name][item.id] = item


func _uncache_item(table_name: String, id: int) -> void:
	if _id_cache.has(table_name):
		_id_cache[table_name].erase(id)


# --- Inheritance -------------------------------------------------------------

## Get parent table via script reflection (get_base_script)
func get_parent_table(table_name: String) -> String:
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	var script: GDScript = _load_fresh_script(script_path)
	if script == null:
		return ""

	var base: GDScript = script.get_base_script()
	if base == null:
		return ""

	# Check if base is DataItem (no parent table)
	var base_path_str: String = base.resource_path
	if base_path_str.is_empty():
		return ""

	# If the base script is in our structures directory, extract the table name
	if base_path_str.begins_with(structures_path):
		var file_name := base_path_str.get_file().get_basename()
		# Find the matching table name (case-sensitive) from known tables
		for name in get_table_names():
			if name.to_lower() == file_name:
				return name
	return ""


func get_child_tables(table_name: String) -> Array[String]:
	var children: Array[String] = []
	for name in get_table_names():
		if get_parent_table(name) == table_name:
			children.append(name)
	return children


## Get only the fields declared in this table's own script (excluding inherited fields).
func get_own_table_fields(table_name: String) -> Array[Dictionary]:
	var all_fields: Array[Dictionary] = get_table_fields(table_name)
	var parent_name: String = get_parent_table(table_name)
	if parent_name.is_empty():
		return all_fields

	var parent_fields: Array[Dictionary] = get_table_fields(parent_name)
	var parent_names: Array[String] = []
	for pf in parent_fields:
		parent_names.append(pf.name)

	var own: Array[Dictionary] = []
	for f in all_fields:
		if f.name not in parent_names:
			own.append(f)
	return own


## Returns the inheritance chain from DataItem → ... → parent → this table.
func get_inheritance_chain(table_name: String) -> Array[Dictionary]:
	var chain: Array[Dictionary] = []
	var current: String = table_name
	while not current.is_empty():
		chain.push_front({
			"table_name": current,
			"fields": get_own_table_fields(current)
		})
		current = get_parent_table(current)
	# Prepend DataItem base fields (name, id)
	chain.push_front({
		"table_name": "DataItem",
		"fields": [
			{"name": "name", "type": TYPE_STRING, "default": ""},
			{"name": "id", "type": TYPE_INT, "default": -1}
		]
	})
	return chain


## Get all instances of a table AND all its descendants (polymorphic query).
func get_data_items_polymorphic(table_name: String) -> Array[DataItem]:
	var items: Array[DataItem] = []
	items.append_array(get_data_items(table_name))
	for child_name in get_child_tables(table_name):
		items.append_array(get_data_items_polymorphic(child_name))
	return items


func _would_create_cycle(table_name: String, parent_name: String) -> bool:
	var current: String = parent_name
	while not current.is_empty():
		if current == table_name:
			return true
		current = get_parent_table(current)
	return false


func is_descendant_of(table_name: String, potential_ancestor: String) -> bool:
	var current: String = get_parent_table(table_name)
	while not current.is_empty():
		if current == potential_ancestor:
			return true
		current = get_parent_table(current)
	return false


## Regenerate a child table's script after parent rename
func _regenerate_child_script_for_rename(child_name: String,
		new_parent_name: String) -> void:
	var own_fields: Array[Dictionary] = get_own_table_fields(child_name)
	var gen_fields: Array[Dictionary] = []
	for f in own_fields:
		gen_fields.append({
			"name": f.name,
			"type_string": ResourceGenerator.property_info_to_type_string(f),
			"default": f.default
		})
	var constraints: Dictionary = get_field_constraints(child_name)
	ResourceGenerator.generate_resource_class(
		child_name, gen_fields, structures_path, constraints, new_parent_name)

	var script_path := structures_path.path_join("%s.gd" % child_name.to_lower())
	var cached_script: GDScript = load(script_path) as GDScript
	if cached_script:
		cached_script.source_code = FileAccess.get_file_as_string(script_path)
		cached_script.reload(true)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(script_path)


# --- Internal ----------------------------------------------------------------

func _create_data_item(table_name: String) -> DataItem:
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	if not ResourceLoader.exists(script_path):
		push_error("Resource script not found: %s" % script_path)
		return null

	var script = ResourceLoader.load(
		script_path, "", ResourceLoader.CACHE_MODE_REUSE
	) as GDScript
	if script == null:
		return null

	return script.new()


## Load a .gd script fresh from disk, bypassing all Godot caching.
## Creates an anonymous GDScript (strips class_name) so reload() is safe.
func _load_fresh_script(script_path: String) -> GDScript:
	var abs_path := ProjectSettings.globalize_path(script_path)
	if not FileAccess.file_exists(abs_path):
		return null

	var source := FileAccess.get_file_as_string(abs_path)
	if source.is_empty():
		return null

	# Strip class_name to make it anonymous (avoids conflicts with cached version)
	var lines := source.split("\n")
	var filtered_lines: PackedStringArray = []
	for line in lines:
		if not line.strip_edges().begins_with("class_name"):
			filtered_lines.append(line)
	source = "\n".join(filtered_lines)

	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script


## Scan table_structures/ directory for .gd files → table names
func _scan_table_names() -> Array[String]:
	var names: Array[String] = []
	if not DirAccess.dir_exists_absolute(structures_path):
		return names

	var dir := DirAccess.open(structures_path)
	if dir == null:
		return names

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			# Read class_name from the script to get the proper-case table name
			var class_name_str := _read_class_name(
				structures_path.path_join(file_name))
			if not class_name_str.is_empty():
				names.append(class_name_str)
		file_name = dir.get_next()
	dir.list_dir_end()
	return names


## Read class_name from a .gd file
func _read_class_name(script_path: String) -> String:
	var source := FileAccess.get_file_as_string(script_path)
	if source.is_empty():
		return ""
	for line in source.split("\n"):
		line = line.strip_edges()
		if line.begins_with("class_name "):
			return line.substr(11).strip_edges()
	return ""


func _scan_filesystem() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _request_scan() -> void:
	# Simple scan for now — Phase 3 will add debouncing
	_scan_filesystem()
