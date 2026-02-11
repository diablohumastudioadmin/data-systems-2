@tool
class_name Database
extends Resource

## Centralized database resource containing all schemas and instances
## Single source of truth stored as res://data/database.tres

## Dictionary of type name -> schema data (as Dictionary)
## Schema format: {type_name, is_user_data, properties[]}
@export var schemas: Dictionary = {}

## Dictionary of type name -> Array[DataItem]
## Contains all instances for all types
@export var instances: Dictionary = {}

## Database version for future migrations
@export var version: int = 1

## Last modified timestamp
@export var last_modified: String = ""


func _init() -> void:
	last_modified = Time.get_datetime_string_from_system()


## Get schema by name
func get_schema(type_name: String) -> Dictionary:
	return schemas.get(type_name, {})


## Check if schema exists
func has_schema(type_name: String) -> bool:
	return schemas.has(type_name)


## Add or update schema
func set_schema(type_name: String, schema_data: Dictionary) -> void:
	schemas[type_name] = schema_data
	last_modified = Time.get_datetime_string_from_system()


## Remove schema
func remove_schema(type_name: String) -> void:
	schemas.erase(type_name)
	instances.erase(type_name)
	last_modified = Time.get_datetime_string_from_system()


## Get all schema names
func get_schema_names() -> Array[String]:
	var names: Array[String] = []
	names.assign(schemas.keys())
	return names


## Get instances for a type
func get_instances(type_name: String) -> Array[DataItem]:
	if not instances.has(type_name):
		instances[type_name] = []

	var result: Array[DataItem] = []
	var items = instances.get(type_name, [])

	# Ensure proper type
	if items is Array:
		result.assign(items)

	return result


## Set instances for a type
func set_instances(type_name: String, items: Array[DataItem]) -> void:
	instances[type_name] = items
	last_modified = Time.get_datetime_string_from_system()


## Check if type has any instances
func has_instances(type_name: String) -> bool:
	return instances.has(type_name) and not instances[type_name].is_empty()
