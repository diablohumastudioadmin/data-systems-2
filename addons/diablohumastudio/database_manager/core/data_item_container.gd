@tool
class_name DataItemContainer
extends Resource

## Container resource for storing arrays of DataItem instances as .tres files

@export var type_name: String = ""
@export var instances: Array[DataItem] = []
