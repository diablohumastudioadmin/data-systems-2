@tool
class_name DatabaseSystem
extends RefCounted

## Single orchestrator for the database system.
## Manages tables (via generated .gd scripts) and instances (via DataTable).

signal data_changed(table_name: String)
signal tables_changed()

## Known properties from base classes to exclude from schema reflection
const _BASE_PROPERTY_NAMES: Array[String] = [
	"resource_local_to_scene", "resource_path", "resource_name", "script"
]

var _storage_adapter: StorageAdapter
var _database: Database


func _init() -> void:
	_storage_adapter = ResourceStorageAdapter.new()
	_database = _storage_adapter.load_database()


func save() -> Error:
	return _storage_adapter.save_database(_database)


# --- Table Management --------------------------------------------------------

func get_table_names() -> Array[String]:
	return _database.get_table_names()


func get_table(table_name: String) -> DataTable:
	return _database.get_table(table_name)


func has_table(table_name: String) -> bool:
	return _database.has_table(table_name)


## Read schema from the generated .gd script via reflection.
## Only returns @export properties declared in the generated subclass.
## Returns: [{name, type (Variant.Type), default, hint, hint_string, class_name}, ...]
func get_table_properties(table_name: String) -> Array[Dictionary]:
	var script_path = "res://database/res/table_structures/%s.gd" % table_name.to_lower()
	var script: GDScript = _load_fresh_script(script_path)
	if script == null:
		return []

	var temp = script.new()
	var props: Array[Dictionary] = []
	for p in script.get_script_property_list():
		# Only include @export properties (have EDITOR usage flag)
		if not (p.usage & PROPERTY_USAGE_EDITOR):
			continue
		# Skip base class properties
		if p.name in _BASE_PROPERTY_NAMES:
			continue
		props.append({
			"name": p.name,
			"type": p.type,
			"default": temp.get(p.name),
			"hint": p.get("hint", PROPERTY_HINT_NONE),
			"hint_string": p.get("hint_string", ""),
			"class_name": p.get("class_name", "")
		})
	return props


## Check if a table has a specific property
func table_has_property(table_name: String, property_name: String) -> bool:
	var props = get_table_properties(table_name)
	for p in props:
		if p.name == property_name:
			return true
	return false


## Add a new table (generates .gd file + creates DataTable)
## properties: Array of {name: String, type: ResourceGenerator.PropertyType, default: Variant}
func add_table(table_name: String, properties: Array[Dictionary]) -> bool:
	if _database.has_table(table_name):
		push_warning("Table already exists: %s" % table_name)
		return false

	ResourceGenerator.generate_resource_class(table_name, properties)

	var table := DataTable.new()
	table.table_name = table_name
	_database.add_table(table)

	var err := save()
	if err != OK:
		push_error("Failed to save after adding table: %s" % table_name)
		return false

	_scan_filesystem()
	tables_changed.emit()
	return true


## Update an existing table (regenerates .gd file)
func update_table(table_name: String, properties: Array[Dictionary]) -> bool:
	if not _database.has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	ResourceGenerator.generate_resource_class(table_name, properties)

	var err := save()
	if err != OK:
		push_error("Failed to save after updating table: %s" % table_name)
		return false

	_scan_filesystem()
	tables_changed.emit()
	return true


## Remove a table (deletes .gd file + removes DataTable)
func remove_table(table_name: String) -> bool:
	if not _database.has_table(table_name):
		push_warning("Table not found: %s" % table_name)
		return false

	_database.remove_table(table_name)
	ResourceGenerator.delete_resource_class(table_name)

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


## Add a new instance with default values from the generated script
func add_instance(table_name: String) -> bool:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		push_error("Table not found: %s" % table_name)
		return false

	var item: DataItem = _create_data_item(table_name)
	if item == null:
		return false

	table.instances.append(item)
	save()
	data_changed.emit(table_name)
	return true


func remove_instance(table_name: String, index: int) -> bool:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return false
	if index < 0 or index >= table.instances.size():
		return false

	table.instances.remove_at(index)
	save()
	data_changed.emit(table_name)
	return true


func save_instances(_table_name: String) -> Error:
	return save()


func load_instances(_table_name: String) -> void:
	# Reload from disk (for refresh button)
	_database = _storage_adapter.load_database()


func clear_instances(table_name: String) -> void:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return
	table.instances.clear()
	save()
	data_changed.emit(table_name)


func get_instance_count(table_name: String) -> int:
	var table: DataTable = _database.get_table(table_name)
	if table == null:
		return 0
	return table.instances.size()


func _create_data_item(table_name: String) -> DataItem:
	var script_path := "res://database/res/table_structures/%s.gd" % table_name.to_lower()
	if not ResourceLoader.exists(script_path):
		push_error("Resource script not found: %s" % script_path)
		return null

	var script = ResourceLoader.load(
		script_path, "", ResourceLoader.CACHE_MODE_REPLACE
	) as GDScript
	if script == null:
		return null

	# script.new() already has all @export defaults applied
	return script.new()


## Load a .gd script fresh from disk, bypassing all Godot caching.
## Creates an anonymous GDScript (strips class_name) so reload() is safe
## (no live instances reference it). Used for schema reflection.
func _load_fresh_script(script_path: String) -> GDScript:
	var abs_path := ProjectSettings.globalize_path(script_path)
	if not FileAccess.file_exists(abs_path):
		return null

	var source := FileAccess.get_file_as_string(abs_path)
	if source.is_empty():
		return null

	# Strip class_name line to avoid global registration conflicts
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


func _scan_filesystem() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
