class_name UserDataManager
extends RefCounted

## Manages user-specific data instances

signal data_changed(user_id: String, type_name: String)

var type_registry: DataTypeRegistry
var user_data: Dictionary = {}  # user_id -> {type_name -> Array[Dictionary]}


func _init(p_type_registry: DataTypeRegistry) -> void:
	type_registry = p_type_registry


## Initialize default data for a new user
func initialize_user_data(user_id: String) -> void:
	if user_data.has(user_id):
		return

	user_data[user_id] = {}

	# Create default instances for all user data types
	for type_name in type_registry.get_user_type_names():
		user_data[user_id][type_name] = []

	print("[UserDataManager] Initialized data for user: %s" % user_id)


## Add data instance for user
func add_instance(user_id: String, type_name: String, instance_data: Dictionary) -> bool:
	if !user_data.has(user_id):
		initialize_user_data(user_id)

	if !user_data[user_id].has(type_name):
		user_data[user_id][type_name] = []

	# Validate against type definition
	var type_def = type_registry.get_type(type_name, true)
	if type_def == null:
		push_error("User data type not found: %s" % type_name)
		return false

	user_data[user_id][type_name].append(instance_data)
	data_changed.emit(user_id, type_name)
	return true


## Remove data instance by index
func remove_instance(user_id: String, type_name: String, index: int) -> bool:
	if !user_data.has(user_id) or !user_data[user_id].has(type_name):
		return false

	var instances = user_data[user_id][type_name]
	if index < 0 or index >= instances.size():
		return false

	instances.remove_at(index)
	data_changed.emit(user_id, type_name)
	return true


## Update data instance
func update_instance(user_id: String, type_name: String, index: int, instance_data: Dictionary) -> bool:
	if !user_data.has(user_id) or !user_data[user_id].has(type_name):
		return false

	var instances = user_data[user_id][type_name]
	if index < 0 or index >= instances.size():
		return false

	instances[index] = instance_data
	data_changed.emit(user_id, type_name)
	return true


## Get all instances for a type and user
func get_instances(user_id: String, type_name: String) -> Array:
	if !user_data.has(user_id) or !user_data[user_id].has(type_name):
		return []
	return user_data[user_id][type_name]


## Get instance by index
func get_instance(user_id: String, type_name: String, index: int) -> Dictionary:
	var instances = get_instances(user_id, type_name)
	if index >= 0 and index < instances.size():
		return instances[index]
	return {}


## Get instance by property value
func get_instance_by(user_id: String, type_name: String, property_name: String, value: Variant) -> Dictionary:
	var instances = get_instances(user_id, type_name)
	for instance in instances:
		if instance.get(property_name) == value:
			return instance
	return {}


## Find index of instance by property value
func find_instance_index(user_id: String, type_name: String, property_name: String, value: Variant) -> int:
	var instances = get_instances(user_id, type_name)
	for i in range(instances.size()):
		if instances[i].get(property_name) == value:
			return i
	return -1


## Update instance property by finding it first
func update_instance_property(user_id: String, type_name: String, property_name: String, property_value: Variant, new_data: Dictionary) -> bool:
	var index = find_instance_index(user_id, type_name, property_name, property_value)
	if index == -1:
		return false

	return update_instance(user_id, type_name, index, new_data)


## Set a specific property value on an instance
func set_instance_property(user_id: String, type_name: String, instance_index: int, property_name: String, value: Variant) -> bool:
	var instance = get_instance(user_id, type_name, instance_index)
	if instance.is_empty():
		return false

	instance[property_name] = value
	return update_instance(user_id, type_name, instance_index, instance)


## Clear all instances for a type
func clear_instances(user_id: String, type_name: String) -> void:
	if user_data.has(user_id) and user_data[user_id].has(type_name):
		user_data[user_id][type_name].clear()
		data_changed.emit(user_id, type_name)


## Get all user data for a user
func get_user_data(user_id: String) -> Dictionary:
	return user_data.get(user_id, {})


## Set all user data for a user (used by persistence)
func set_user_data(user_id: String, data: Dictionary) -> void:
	user_data[user_id] = data


## Clear all data for a user
func clear_user_data(user_id: String) -> void:
	if user_data.has(user_id):
		user_data.erase(user_id)
