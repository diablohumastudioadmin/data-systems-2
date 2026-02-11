@tool
class_name GameDataSystem
extends RefCounted

## Game Data System
## Manages data type definitions and data instances

signal data_changed(type_name: String)  # Emitted when data instances change

var type_registry: DataTypeRegistry
var _instances: Dictionary = {}  # type_name -> Array[DataItem] (private)
var _storage_adapter: StorageAdapter


func _init() -> void:
	# Create storage adapter first
	_storage_adapter = ResourceStorageAdapter.new()
	# Pass storage adapter to registry so they share the same database
	type_registry = DataTypeRegistry.new(_storage_adapter)
	load_all_instances()


## Load all data instances for all types
func load_all_instances() -> void:
	_instances.clear()

	for type_name in type_registry.get_game_type_names():
		load_instances(type_name)

	print("[GameDataSystem] Loaded instances for %d types" % _instances.size())


## Load data instances for a specific type
func load_instances(type_name: String) -> Error:
	_instances[type_name] = _storage_adapter.load_instances(type_name)
	print("[GameDataSystem] Loaded %d instances of %s" % [_instances[type_name].size(), type_name])
	return OK


## Save data instances for a specific type
func save_instances(type_name: String) -> Error:
	if not _instances.has(type_name):
		return OK

	# Convert to typed array properly
	var items: Array[DataItem] = []
	items.assign(_instances[type_name])

	var err := _storage_adapter.save_instances(type_name, items)
	if err == OK:
		print("[GameDataSystem] Saved %d instances of %s" % [items.size(), type_name])
	else:
		push_error("Failed to save instances for type: %s" % type_name)
	return err


## Add a new data instance
func add_instance(type_name: String, instance_data: Dictionary) -> bool:
	# Ensure typed array exists
	if not _instances.has(type_name):
		var empty: Array[DataItem] = []
		_instances[type_name] = empty

	# Validate against type definition
	var type_def := type_registry.get_type(type_name)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return false

	if not type_def.validate_instance(instance_data):
		push_warning("Instance validation failed for type: %s" % type_name)

	# Convert Dictionary -> DataItem Resource
	var item := _create_data_item(type_name, instance_data)
	if item == null:
		return false

	# Get as typed array, append, and store back
	var items: Array[DataItem] = []
	items.assign(_instances[type_name])
	items.append(item)
	_instances[type_name] = items

	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Remove a data instance by index
func remove_instance(type_name: String, index: int) -> bool:
	if not _instances.has(type_name):
		return false

	var items: Array[DataItem] = []
	items.assign(_instances[type_name])

	if index < 0 or index >= items.size():
		return false

	items.remove_at(index)
	_instances[type_name] = items
	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Update a data instance
func update_instance(type_name: String, index: int, instance_data: Dictionary) -> bool:
	if not _instances.has(type_name):
		return false

	var items: Array[DataItem] = []
	items.assign(_instances[type_name])

	if index < 0 or index >= items.size():
		return false

	# Validate against type definition
	var type_def := type_registry.get_type(type_name)
	if type_def != null:
		if not type_def.validate_instance(instance_data):
			push_warning("Instance validation failed for type: %s" % type_name)

	# Update existing DataItem in place
	items[index].from_dict(instance_data)
	_instances[type_name] = items

	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Get all instances for a type
func get_instances(type_name: String) -> Array:
	# Convert DataItem -> Dictionary for UI
	if not _instances.has(type_name):
		return []

	var items: Array[DataItem] = []
	items.assign(_instances[type_name])

	var result: Array = []
	for item in items:
		result.append(item.to_dict())

	return result


## Get actual DataItem resources for a type (for direct Inspector editing)
## Unlike get_instances() which returns dictionaries, this returns the live Resources
func get_data_items(type_name: String) -> Array[DataItem]:
	if not _instances.has(type_name):
		return []
	var items: Array[DataItem] = []
	items.assign(_instances[type_name])
	return items


## Get instance by index
func get_instance(type_name: String, index: int) -> Dictionary:
	var instances = get_instances(type_name)
	if index >= 0 and index < instances.size():
		return instances[index]
	return {}


## Get instance by property value (e.g., by id)
func get_instance_by(type_name: String, property_name: String, value: Variant) -> Dictionary:
	var instances = get_instances(type_name)
	for instance in instances:
		if instance.get(property_name) == value:
			return instance
	return {}


## Create a new instance with default values
func create_default_instance(type_name: String) -> Dictionary:
	var type_def = type_registry.get_type(type_name)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return {}

	return type_def.create_default_instance()


## Delete all instances for a type
func clear_instances(type_name: String) -> void:
	if _instances.has(type_name):
		var empty: Array[DataItem] = []
		_instances[type_name] = empty
		save_instances(type_name)
		data_changed.emit(type_name)


## Get count of instances for a type
func get_instance_count(type_name: String) -> int:
	return get_instances(type_name).size()


## Helper method to create DataItem instances
func _create_data_item(type_name: String, data: Dictionary) -> DataItem:
	# Load the generated Resource class
	var script_path := "res://addons/diablohumastudio/database_manager/resources/%s.gd" % type_name.to_lower()

	if not ResourceLoader.exists(script_path):
		push_error("Resource script not found: %s" % script_path)
		return null

	var script := load(script_path) as GDScript
	if script == null:
		return null

	var item: DataItem = script.new()
	item.from_dict(data)
	return item
