@tool
class_name DatabaseSystem
extends RefCounted

## Single orchestrator for the database system.
## Manages types (via generated .gd scripts) and instances (via DataTable).

signal data_changed(type_name: String)
signal types_changed()

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


# --- Type/Table Management ---------------------------------------------------

func get_table_names() -> Array[String]:
	return _database.get_table_names()


func get_table(type_name: String) -> DataTable:
	return _database.get_table(type_name)


func has_type(type_name: String) -> bool:
	return _database.has_table(type_name)


## Read schema from the generated .gd script via reflection.
## Only returns @export properties declared in the generated subclass.
## Returns: [{name, type (Variant.Type), default, hint, hint_string, class_name}, ...]
func get_type_properties(type_name: String) -> Array[Dictionary]:
	var script_path = "res://database/res/table_structures/%s.gd" % type_name.to_lower()
	if not ResourceLoader.exists(script_path):
		return []

	# CACHE_MODE_REPLACE forces reload from disk (critical after regeneration)
	var script = ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REPLACE) as GDScript
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


## Check if a type has a specific property
func type_has_property(type_name: String, property_name: String) -> bool:
	var props = get_type_properties(type_name)
	for p in props:
		if p.name == property_name:
			return true
	return false


## Add a new type (generates .gd file + creates DataTable)
## properties: Array of {name: String, type: ResourceGenerator.PropertyType, default: Variant}
func add_type(type_name: String, properties: Array[Dictionary]) -> bool:
	if _database.has_table(type_name):
		push_warning("Type already exists: %s" % type_name)
		return false

	ResourceGenerator.generate_resource_class(type_name, properties)

	var table := DataTable.new()
	table.type_name = type_name
	_database.add_table(table)

	var err := save()
	if err != OK:
		push_error("Failed to save after adding type: %s" % type_name)
		return false

	_scan_filesystem()
	types_changed.emit()
	return true


## Update an existing type (regenerates .gd file)
func update_type(type_name: String, properties: Array[Dictionary]) -> bool:
	if not _database.has_table(type_name):
		push_warning("Type not found: %s" % type_name)
		return false

	ResourceGenerator.generate_resource_class(type_name, properties)

	var err := save()
	if err != OK:
		push_error("Failed to save after updating type: %s" % type_name)
		return false

	_scan_filesystem()
	types_changed.emit()
	return true


## Remove a type (deletes .gd file + removes DataTable)
func remove_type(type_name: String) -> bool:
	if not _database.has_table(type_name):
		push_warning("Type not found: %s" % type_name)
		return false

	_database.remove_table(type_name)
	ResourceGenerator.delete_resource_class(type_name)

	var err := save()
	if err != OK:
		push_error("Failed to save after removing type: %s" % type_name)
		return false

	_scan_filesystem()
	types_changed.emit()
	return true


# --- Instance Management -----------------------------------------------------

func get_data_items(type_name: String) -> Array[DataItem]:
	var table: DataTable = _database.get_table(type_name)
	if table == null:
		return []
	var items: Array[DataItem] = []
	items.assign(table.instances)
	return items


## Add a new instance with default values from the generated script
func add_instance(type_name: String) -> bool:
	var table: DataTable = _database.get_table(type_name)
	if table == null:
		push_error("Table not found: %s" % type_name)
		return false

	var item: DataItem = _create_data_item(type_name)
	if item == null:
		return false

	table.instances.append(item)
	save()
	data_changed.emit(type_name)
	return true


func remove_instance(type_name: String, index: int) -> bool:
	var table: DataTable = _database.get_table(type_name)
	if table == null:
		return false
	if index < 0 or index >= table.instances.size():
		return false

	table.instances.remove_at(index)
	save()
	data_changed.emit(type_name)
	return true


func save_instances(_type_name: String) -> Error:
	return save()


func load_instances(_type_name: String) -> void:
	# Reload from disk (for refresh button)
	_database = _storage_adapter.load_database()


func clear_instances(type_name: String) -> void:
	var table: DataTable = _database.get_table(type_name)
	if table == null:
		return
	table.instances.clear()
	save()
	data_changed.emit(type_name)


func get_instance_count(type_name: String) -> int:
	var table: DataTable = _database.get_table(type_name)
	if table == null:
		return 0
	return table.instances.size()


func _create_data_item(type_name: String) -> DataItem:
	var script_path := "res://database/res/table_structures/%s.gd" % type_name.to_lower()
	if not ResourceLoader.exists(script_path):
		push_error("Resource script not found: %s" % script_path)
		return null

	# CACHE_MODE_REPLACE forces reload from disk (critical after regeneration)
	var script := ResourceLoader.load(
		script_path, "", ResourceLoader.CACHE_MODE_REPLACE
	) as GDScript
	if script == null:
		return null

	# script.new() already has all @export defaults applied
	return script.new()


func _scan_filesystem() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
