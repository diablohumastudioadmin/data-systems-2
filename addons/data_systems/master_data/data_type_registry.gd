@tool
class_name DataTypeRegistry
extends RefCounted

## Manages all data type definitions (master and user data)
## Handles loading/saving type definitions from JSON

signal types_changed()  # Emitted when types are added/removed/modified

const TYPES_FILE_PATH = "res://data/master_data_types.json"

var master_types: Dictionary = {}  # type_name -> DataTypeDefinition
var user_types: Dictionary = {}    # type_name -> DataTypeDefinition


func _init() -> void:
	load_types()


## Load all type definitions from disk
func load_types() -> Error:
	if !JSONPersistence.file_exists(TYPES_FILE_PATH):
		print("[DataTypeRegistry] No types file found, creating new one")
		_create_default_types_file()
		return OK

	var data = JSONPersistence.load_json(TYPES_FILE_PATH)
	if data == null:
		push_error("Failed to load types from: %s" % TYPES_FILE_PATH)
		return ERR_FILE_CORRUPT

	# Parse master types
	master_types.clear()
	var master_data = data.get("master_types", {})
	for type_name in master_data.keys():
		var type_def = DataTypeDefinition.from_dict(master_data[type_name])
		type_def.type_name = type_name
		type_def.is_user_data = false
		master_types[type_name] = type_def

	# Parse user types
	user_types.clear()
	var user_data = data.get("user_types", {})
	for type_name in user_data.keys():
		var type_def = DataTypeDefinition.from_dict(user_data[type_name])
		type_def.type_name = type_name
		type_def.is_user_data = true
		user_types[type_name] = type_def

	print("[DataTypeRegistry] Loaded %d master types, %d user types" % [master_types.size(), user_types.size()])
	types_changed.emit()
	return OK


## Save all type definitions to disk
func save_types() -> Error:
	var data = {
		"master_types": {},
		"user_types": {}
	}

	# Serialize master types
	for type_name in master_types.keys():
		data.master_types[type_name] = master_types[type_name].to_dict()

	# Serialize user types
	for type_name in user_types.keys():
		data.user_types[type_name] = user_types[type_name].to_dict()

	var error = JSONPersistence.save_json(TYPES_FILE_PATH, data)
	if error == OK:
		print("[DataTypeRegistry] Saved types to: %s" % TYPES_FILE_PATH)
	else:
		push_error("Failed to save types to: %s" % TYPES_FILE_PATH)

	return error


## Add a new type definition
func add_type(definition: DataTypeDefinition) -> bool:
	var type_dict = master_types if !definition.is_user_data else user_types

	if type_dict.has(definition.type_name):
		push_warning("Type already exists: %s" % definition.type_name)
		return false

	type_dict[definition.type_name] = definition

	# Generate Resource class for master data types
	if !definition.is_user_data:
		ResourceGenerator.generate_resource_class(definition)

	save_types()
	types_changed.emit()
	return true


## Remove a type definition
func remove_type(type_name: String, is_user_data: bool) -> bool:
	var type_dict = user_types if is_user_data else master_types

	if !type_dict.has(type_name):
		push_warning("Type not found: %s" % type_name)
		return false

	type_dict.erase(type_name)

	# Delete Resource class for master data types
	if !is_user_data:
		ResourceGenerator.delete_resource_class(type_name)

	save_types()
	types_changed.emit()
	return true


## Update an existing type definition
func update_type(definition: DataTypeDefinition) -> bool:
	var type_dict = master_types if !definition.is_user_data else user_types

	if !type_dict.has(definition.type_name):
		push_warning("Type not found: %s" % definition.type_name)
		return false

	type_dict[definition.type_name] = definition

	# Regenerate Resource class for master data types
	if !definition.is_user_data:
		ResourceGenerator.generate_resource_class(definition)

	save_types()
	types_changed.emit()
	return true


## Get a type definition
func get_type(type_name: String, is_user_data: bool = false) -> DataTypeDefinition:
	var type_dict = user_types if is_user_data else master_types
	return type_dict.get(type_name, null)


## Get all master type names
func get_master_type_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(master_types.keys())
	return names


## Get all user type names
func get_user_type_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(user_types.keys())
	return names


## Get all master type definitions
func get_master_types() -> Array[DataTypeDefinition]:
	var types: Array[DataTypeDefinition] = []
	types.assign(master_types.values())
	return types


## Get all user type definitions
func get_user_types() -> Array[DataTypeDefinition]:
	var types: Array[DataTypeDefinition] = []
	types.assign(user_types.values())
	return types


## Check if type exists
func has_type(type_name: String, is_user_data: bool = false) -> bool:
	var type_dict = user_types if is_user_data else master_types
	return type_dict.has(type_name)


## Regenerate all Resource classes
func regenerate_all_resources() -> void:
	var definitions = get_master_types()
	ResourceGenerator.regenerate_all_resources(definitions)
	print("[DataTypeRegistry] Regenerated all resource classes")


## Create default types file
func _create_default_types_file() -> void:
	var data = {
		"master_types": {},
		"user_types": {}
	}
	JSONPersistence.save_json(TYPES_FILE_PATH, data)
