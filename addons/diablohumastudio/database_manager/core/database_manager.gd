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

const DEFAULT_BASE_PATH := "res://database/res/"

var base_path: String = DEFAULT_BASE_PATH:
	set(value):
		base_path = value
		if _storage != null:
			reload()
var structures_path: String:
	get: return base_path.path_join("table_structures/")
var instances_path: String:
	get: return base_path.path_join("instances/")

# Public Modules
var schema: SchemaManager
var instances: InstanceManager

var _storage: StorageAdapter

func _init() -> void:
	_storage = ResourceStorageAdapter.new()


func _ready() -> void:
	reload()


# --- Core -------------------------------------------------------------------

func reload() -> void:
	if MigrationHelper.needs_migration(base_path):
		MigrationHelper.migrate_v1_to_v2(base_path, _storage)
	
	schema = SchemaManager.new(base_path)
	instances = InstanceManager.new(_storage, schema, base_path)
	
	# Connect dependencies
	schema.instance_manager = instances
	
	# Connect signals
	if not schema.tables_changed.is_connected(func(): tables_changed.emit()):
		schema.tables_changed.connect(func(): tables_changed.emit())
		
	if not instances.data_changed.is_connected(func(t): data_changed.emit(t)):
		instances.data_changed.connect(func(t): data_changed.emit(t))
	
	tables_changed.emit()


# --- Table Management (Delegated to SchemaManager) ---------------------------

func get_table_names() -> Array[String]:
	return schema.get_table_names()

func has_table(table_name: String) -> bool:
	return schema.has_table(table_name)

func get_table_fields(table_name: String) -> Array[Dictionary]:
	return schema.get_table_fields(table_name)

func table_has_field(table_name: String, field_name: String) -> bool:
	return schema.table_has_field(table_name, field_name)

func get_field_constraints(table_name: String) -> Dictionary:
	return schema.get_field_constraints(table_name)

func add_table(table_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	return schema.add_table(table_name, fields, constraints, parent_table)

func update_table(table_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	return schema.update_table(table_name, fields, constraints, parent_table)

func rename_table(old_name: String, new_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, parent_table: String = "") -> bool:
	return schema.rename_table(old_name, new_name, fields, constraints, parent_table)

func remove_table(table_name: String) -> bool:
	return schema.remove_table(table_name)

# --- Instance Management (Delegated to InstanceManager) ----------------------

func get_data_items(table_name: String) -> Array[DataItem]:
	return instances.get_data_items(table_name)

func get_by_id(table_name: String, id: int) -> DataItem:
	return instances.get_by_id(table_name, id)

func add_instance(table_name: String, instance_name: String) -> DataItem:
	return instances.add_instance(table_name, instance_name)

func remove_instance(table_name: String, id: int) -> bool:
	return instances.remove_instance(table_name, id)

func save_instances(table_name: String) -> Error:
	return instances.save_instances(table_name)

func load_instances(table_name: String) -> void:
	instances.load_instances(table_name)

func clear_instances(table_name: String) -> void:
	instances.clear_instances(table_name)

func get_instance_count(table_name: String) -> int:
	return instances.get_instance_count(table_name)

# --- Inheritance (Delegated to SchemaManager) --------------------------------

func get_parent_table(table_name: String) -> String:
	return schema.get_parent_table(table_name)

func get_child_tables(table_name: String) -> Array[String]:
	return schema.get_child_tables(table_name)

func get_own_table_fields(table_name: String) -> Array[Dictionary]:
	return schema.get_own_table_fields(table_name)

func get_inheritance_chain(table_name: String) -> Array[Dictionary]:
	return schema.get_inheritance_chain(table_name)

func get_data_items_polymorphic(table_name: String) -> Array[DataItem]:
	var items: Array[DataItem] = []
	items.append_array(get_data_items(table_name))
	for child_name in get_child_tables(table_name):
		items.append_array(get_data_items_polymorphic(child_name))
	return items

func is_descendant_of(table_name: String, potential_ancestor: String) -> bool:
	return schema.is_descendant_of(table_name, potential_ancestor)

# --- Internal (Delegated) ----------------------------------------------------

func _request_scan() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
