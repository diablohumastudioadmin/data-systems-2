@tool
class_name GameDataSystem
extends RefCounted

## Game Data System
## Manages data type definitions and data instances

signal data_changed(type_name: String)  # Emitted when data instances change

var type_registry: DataTypeRegistry
var data_instances: Dictionary = {}  # type_name -> Array[Dictionary]


func _init() -> void:
	type_registry = DataTypeRegistry.new()
	load_all_instances()


## Load all data instances for all types
func load_all_instances() -> void:
	data_instances.clear()

	for type_name in type_registry.get_game_type_names():
		load_instances(type_name)

	print("[GameDataSystem] Loaded instances for %d types" % data_instances.size())


## Load data instances for a specific type
func load_instances(type_name: String) -> Error:
	var file_path = _get_data_file_path(type_name)

	if !JSONPersistence.file_exists(file_path):
		# Create empty data file
		data_instances[type_name] = []
		save_instances(type_name)
		return OK

	var data = JSONPersistence.load_json(file_path)
	if data == null:
		push_error("Failed to load instances for type: %s" % type_name)
		data_instances[type_name] = []
		return ERR_FILE_CORRUPT

	data_instances[type_name] = data.get("instances", [])
	print("[GameDataSystem] Loaded %d instances of %s" % [data_instances[type_name].size(), type_name])
	return OK


## Save data instances for a specific type
func save_instances(type_name: String) -> Error:
	var file_path = _get_data_file_path(type_name)
	var instances = data_instances.get(type_name, [])

	var data = {
		"type": type_name,
		"instances": instances
	}

	var error = JSONPersistence.save_json(file_path, data)
	if error == OK:
		print("[GameDataSystem] Saved %d instances of %s" % [instances.size(), type_name])
	else:
		push_error("Failed to save instances for type: %s" % type_name)

	return error


## Add a new data instance
func add_instance(type_name: String, instance_data: Dictionary) -> bool:
	if !data_instances.has(type_name):
		data_instances[type_name] = []

	# Validate against type definition
	var type_def = type_registry.get_type(type_name)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return false

	if !type_def.validate_instance(instance_data):
		push_warning("Instance validation failed for type: %s" % type_name)

	data_instances[type_name].append(instance_data)
	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Remove a data instance by index
func remove_instance(type_name: String, index: int) -> bool:
	if !data_instances.has(type_name):
		return false

	var instances = data_instances[type_name]
	if index < 0 or index >= instances.size():
		return false

	instances.remove_at(index)
	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Update a data instance
func update_instance(type_name: String, index: int, instance_data: Dictionary) -> bool:
	if !data_instances.has(type_name):
		return false

	var instances = data_instances[type_name]
	if index < 0 or index >= instances.size():
		return false

	# Validate against type definition
	var type_def = type_registry.get_type(type_name)
	if type_def != null:
		if !type_def.validate_instance(instance_data):
			push_warning("Instance validation failed for type: %s" % type_name)

	instances[index] = instance_data
	save_instances(type_name)
	data_changed.emit(type_name)
	return true


## Get all instances for a type
func get_instances(type_name: String) -> Array:
	return data_instances.get(type_name, [])


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


## Get data file path for a type
func _get_data_file_path(type_name: String) -> String:
	return "res://data/%s.json" % type_name.to_lower()


## Delete all instances for a type
func clear_instances(type_name: String) -> void:
	if data_instances.has(type_name):
		data_instances[type_name].clear()
		save_instances(type_name)
		data_changed.emit(type_name)


## Get count of instances for a type
func get_instance_count(type_name: String) -> int:
	return get_instances(type_name).size()
