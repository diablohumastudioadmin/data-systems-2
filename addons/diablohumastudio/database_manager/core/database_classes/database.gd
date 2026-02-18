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


## Get table by name
func get_table(table_name: String) -> DataTable:
	for table in tables:
		if table.table_name == table_name:
			return table
	return null


## Check if table exists
func has_table(table_name: String) -> bool:
	return get_table(table_name) != null


## Add a table
func add_table(table: DataTable) -> void:
	tables.append(table)
	last_modified = Time.get_datetime_string_from_system()


## Remove a table by name
func remove_table(table_name: String) -> bool:
	for i in range(tables.size()):
		if tables[i].table_name == table_name:
			tables.remove_at(i)
			last_modified = Time.get_datetime_string_from_system()
			return true
	return false


## Get all table names
func get_table_names() -> Array[String]:
	var names: Array[String] = []
	for table in tables:
		names.append(table.table_name)
	return names
