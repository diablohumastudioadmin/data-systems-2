@tool
class_name DataTypeRegistry
extends RefCounted

## Manages all data type definitions (game and user data)
## Handles loading/saving type definitions from centralized database

signal types_changed()  # Emitted when types are added/removed/modified

var game_types: Dictionary = {}  # type_name -> DataTypeDefinition
var user_types: Dictionary = {}  # type_name -> DataTypeDefinition
var _storage_adapter: ResourceStorageAdapter


func _init(storage_adapter: ResourceStorageAdapter = null) -> void:
	if storage_adapter == null:
		_storage_adapter = ResourceStorageAdapter.new()
	else:
		_storage_adapter = storage_adapter
	load_types()


## Load all type definitions from database
func load_types() -> Error:
	var all_schema_names := _storage_adapter.get_all_schema_names()

	game_types.clear()
	user_types.clear()

	for type_name in all_schema_names:
		var schema_dict := _storage_adapter.load_schema(type_name)
		if schema_dict.is_empty():
			continue

		var type_def := DataTypeDefinition.from_dict(schema_dict)
		type_def.type_name = type_name

		if type_def.is_user_data:
			user_types[type_name] = type_def
		else:
			game_types[type_name] = type_def

	print("[DataTypeRegistry] Loaded %d game types, %d user types" % [game_types.size(), user_types.size()])
	types_changed.emit()
	return OK


## Save a single type definition to database
func _save_type(definition: DataTypeDefinition) -> Error:
	var schema_dict := definition.to_dict()
	return _storage_adapter.save_schema(definition.type_name, schema_dict)


## Add a new type definition
func add_type(definition: DataTypeDefinition) -> bool:
	var type_dict = game_types if not definition.is_user_data else user_types

	if type_dict.has(definition.type_name):
		push_warning("Type already exists: %s" % definition.type_name)
		return false

	type_dict[definition.type_name] = definition

	# Generate Resource class for game data types
	if not definition.is_user_data:
		ResourceGenerator.generate_resource_class(definition)

	var err := _save_type(definition)
	if err != OK:
		push_error("Failed to save type: %s" % definition.type_name)
		return false

	types_changed.emit()
	return true


## Remove a type definition
func remove_type(type_name: String, is_user_data: bool) -> bool:
	var type_dict = user_types if is_user_data else game_types

	if not type_dict.has(type_name):
		push_warning("Type not found: %s" % type_name)
		return false

	type_dict.erase(type_name)

	# Delete Resource class for game data types
	if not is_user_data:
		ResourceGenerator.delete_resource_class(type_name)

	var err := _storage_adapter.remove_schema(type_name)
	if err != OK:
		push_error("Failed to remove type: %s" % type_name)
		return false

	types_changed.emit()
	return true


## Update an existing type definition
func update_type(definition: DataTypeDefinition) -> bool:
	var type_dict = game_types if not definition.is_user_data else user_types

	if not type_dict.has(definition.type_name):
		push_warning("Type not found: %s" % definition.type_name)
		return false

	type_dict[definition.type_name] = definition

	# Regenerate Resource class for game data types
	if not definition.is_user_data:
		ResourceGenerator.generate_resource_class(definition)

	var err := _save_type(definition)
	if err != OK:
		push_error("Failed to update type: %s" % definition.type_name)
		return false

	types_changed.emit()
	return true


## Get a type definition
func get_type(type_name: String, is_user_data: bool = false) -> DataTypeDefinition:
	var type_dict = user_types if is_user_data else game_types
	return type_dict.get(type_name, null)


## Get all game type names
func get_game_type_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(game_types.keys())
	return names


## Get all user type names
func get_user_type_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(user_types.keys())
	return names


## Get all game type definitions
func get_game_types() -> Array[DataTypeDefinition]:
	var types: Array[DataTypeDefinition] = []
	types.assign(game_types.values())
	return types


## Get all user type definitions
func get_user_types() -> Array[DataTypeDefinition]:
	var types: Array[DataTypeDefinition] = []
	types.assign(user_types.values())
	return types


## Check if type exists
func has_type(type_name: String, is_user_data: bool = false) -> bool:
	var type_dict = user_types if is_user_data else game_types
	return type_dict.has(type_name)


## Regenerate all Resource classes
func regenerate_all_resources() -> void:
	var definitions = get_game_types()
	ResourceGenerator.regenerate_all_resources(definitions)
	print("[DataTypeRegistry] Regenerated all resource classes")
