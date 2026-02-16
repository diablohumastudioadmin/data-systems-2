@tool
class_name Database
extends Resource

## Centralized database resource containing all tables.
## Saved as a single .tres file at res://database/res/database.tres

@export var tables: Array[DataTable] = []
@export var version: int = 1
@export var last_modified: String = ""


func _init() -> void:
	last_modified = Time.get_datetime_string_from_system()


## Get table by type name
func get_table(type_name: String) -> DataTable:
	for table in tables:
		if table.type_name == type_name:
			return table
	return null


## Check if table exists
func has_table(type_name: String) -> bool:
	return get_table(type_name) != null


## Add a table
func add_table(table: DataTable) -> void:
	tables.append(table)
	last_modified = Time.get_datetime_string_from_system()


## Remove a table by type name
func remove_table(type_name: String) -> bool:
	for i in range(tables.size()):
		if tables[i].type_name == type_name:
			tables.remove_at(i)
			last_modified = Time.get_datetime_string_from_system()
			return true
	return false


## Get all table names
func get_table_names() -> Array[String]:
	var names: Array[String] = []
	for table in tables:
		names.append(table.type_name)
	return names
