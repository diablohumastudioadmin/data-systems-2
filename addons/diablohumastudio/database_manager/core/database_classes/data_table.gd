@tool
class_name DataTable
extends Resource

## A database table: holds a collection of DataItem instances of the same type.
## The schema (property definitions) lives in the generated .gd file at
## res://database/res/table_structures/<table_name>.gd

@export var table_name: String = ""
@export var instances: Array[DataItem] = []
@export var _next_id: int = 0
