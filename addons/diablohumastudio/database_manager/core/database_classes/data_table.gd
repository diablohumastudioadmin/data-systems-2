@tool
class_name DataTable
extends Resource

## A database table: holds a collection of DataItem instances of the same type.
## The schema (property definitions) lives in the generated .gd file at
## res://data/res/table_structures/<type_name>.gd

@export var type_name: String = ""
@export var instances: Array[DataItem] = []
