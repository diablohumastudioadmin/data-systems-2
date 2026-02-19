@tool
class_name DatabaseManager
extends Node

## Single orchestrator for the database system.
## Registered as an autoload by the plugin. Works in editor and at runtime.
## Manages tables (via generated .gd scripts), instances (via DataTable),
## and enum ID files for @export referencing.

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
var ids_path: String:
	get: return base_path.path_join("ids/")
var database_path: String:
	get: return base_path.path_join("database.tres")

var _storage_adapter: StorageAdapter
var _database: Database
var _id_cache: Dictionary = {}  # {table_name: {id_int: DataItem}}


func _init() -> void:
	_storage_adapter = ResourceStorageAdapter.new()


func _ready() -> void:
	reload()


# --- Core -------------------------------------------------------------------

func reload() -> void:
	_database = _storage_adapter.load_database(database_path)
	_migrate_legacy_instances()
	_rebuild_id_cache()


func save() -> Error:
	_database.last_modified = Time.get_datetime_string_from_system()
	return _storage_adapter.save_database(_database, database_path)


# --- Table Management --------------------------------------------------------

func get_table_names() -> Array[String]:
	return _database.get_table_names()


func get_table(table_name: String) -> DataTable:
	return _database.get_table(table_name)


func has_table(table_name: String) -> bool:
	return _database.has_table(table_name)


## Read schema from the generated .gd script via reflection.
## Only returns @export fields declared in the generated subclass.
## Returns: [{name, type (Variant.Type), default, hint, hint_string, class_name}, ...]
func get_table_fields(table_name: String) -> Array[Dictionary]:
	var script_path = structures_path.path_join("%s.gd" % table_name.to_lower())
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


## Add a new table (generates .gd file + creates DataTable)
## fields: Array of {name: String, type: ResourceGenerator.FieldType, default: Variant}
func add_table(table_name: String, fields: Array[Dictionary]) -> bool:
	if _database.has_table(table_name):
		push_warning("Table already exists: %s" % table_name)
		return false

	ResourceGenerator.generate_resource_class(table_name, fields, structures_path)

	var table := DataTable.new()
	table.table_name = table_name
	_database.add_table(table)

	var err := save()
	if err != OK:
		push_error("Failed to save after adding table: %s" % table_name)
		return false

	_regenerate_enum(table_name)
	_scan_filesystem()
	tables_changed.emit()
	return true


## Update an existing table (regenerates .gd file)
func update_table(table_name: String, fields: Array[Dictionary]) -> bool:
	if not _database.has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	ResourceGenerator.generate_resource_class(table_name, fields, structures_path)

	# Reload the script in-place on the EXISTING cached GDScript object.
	# All instances (ours + external editor resources) already hold a reference
	# to that same object, so they all see the updated properties immediately —
	# no set_script() needed. This is the same mechanism Godot uses when you
	# manually re-save a .gd file in the script editor.
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	var cached_script: GDScript = load(script_path) as GDScript
	if cached_script:
		cached_script.source_code = FileAccess.get_file_as_string(script_path)
		cached_script.reload(true)  # keep_state=true preserves existing instance values

	var err := save()
	if err != OK:
		push_error("Failed to save after updating table: %s" % table_name)
		return false

	_rebuild_id_cache()
	# update_file() notifies the editor about the specific changed file so the
	# Script Editor refreshes its buffer; _scan_filesystem() handles class registration.
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(script_path)
	_scan_filesystem()
	tables_changed.emit()
	return true


## Remove a table (deletes .gd file + enum file + removes DataTable)
func remove_table(table_name: String) -> bool:
	if not _database.has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	_database.remove_table(table_name)
	ResourceGenerator.delete_resource_class(table_name, structures_path)
	ResourceGenerator.delete_enum_file(table_name, ids_path)
	_id_cache.erase(table_name)

	var err := save()
	if err != OK:
		push_error("Failed to save after removing table: %s" % table_name)
		return false

	_scan_filesystem()
	tables_changed.emit()
	return true


# --- Instance Management -----------------------------------------------------

func get_data_items(table_name: String) -> Array[DataItem]:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return []
	var items: Array[DataItem] = []
	items.assign(table.instances)
	return items


## Get a specific instance by its stable ID (the enum value)
func get_by_id(table_name: String, id: int) -> DataItem:
	if _id_cache.has(table_name):
		var cache: Dictionary = _id_cache[table_name]
		if cache.has(id):
			return cache[id]
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return null
	for item in table.instances:
		if item.id == id:
			return item
	return null


## Add a new instance with a required name and a stable ID
func add_instance(table_name: String, instance_name: String) -> DataItem:
	if instance_name.strip_edges().is_empty():
		push_error("Instance name cannot be empty")
		return null

	var table: DataTable = _database.get_table(table_name)
	if table == null:
		push_error("Table not found: %s" % table_name)
		return null

	var item: DataItem = _create_data_item(table_name)
	if item == null:
		return null

	item.name = instance_name.strip_edges()
	item.id = table.next_id
	table.next_id += 1

	table.instances.append(item)
	save()
	_cache_item(table_name, item)
	_regenerate_enum(table_name)
	data_changed.emit(table_name)
	return item


func remove_instance(table_name: String, index: int) -> bool:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return false
	if index < 0 or index >= table.instances.size():
		return false

	table.instances.remove_at(index)
	save()
	_rebuild_table_cache(table_name)
	_regenerate_enum(table_name)
	data_changed.emit(table_name)
	return true


func save_instances(table_name: String) -> Error:
	var err := save()
	_rebuild_table_cache(table_name)
	_regenerate_enum(table_name)
	return err


func load_instances(_table_name: String) -> void:
	reload()


func clear_instances(table_name: String) -> void:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return
	table.instances.clear()
	save()
	_rebuild_table_cache(table_name)
	_regenerate_enum(table_name)
	data_changed.emit(table_name)


func get_instance_count(table_name: String) -> int:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return 0
	return table.instances.size()


# --- ID Cache ----------------------------------------------------------------

func _rebuild_id_cache() -> void:
	_id_cache.clear()
	if _database == null:
		return
	for table in _database.tables:
		_rebuild_table_cache(table.table_name)


func _rebuild_table_cache(table_name: String) -> void:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		_id_cache.erase(table_name)
		return
	var cache := {}
	for item in table.instances:
		if item.id >= 0:
			cache[item.id] = item
	_id_cache[table_name] = cache


func _cache_item(table_name: String, item: DataItem) -> void:
	if not _id_cache.has(table_name):
		_id_cache[table_name] = {}
	if item.id >= 0:
		_id_cache[table_name][item.id] = item


# --- Enum Generation ---------------------------------------------------------

func _regenerate_enum(table_name: String) -> void:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return
	ResourceGenerator.generate_enum_file(table_name, table.instances, ids_path)
	_scan_filesystem()


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


## Assign stable IDs to any legacy instances loaded with id == -1
func _migrate_legacy_instances() -> void:
	if _database == null:
		return
	var migrated := false
	for table in _database.tables:
		for item in table.instances:
			if item.id < 0:
				item.id = table.next_id
				table.next_id += 1
				migrated = true
	if migrated:
		save()
		print("[DatabaseManager] Migrated legacy instances with stable IDs")


func _scan_filesystem() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
