@tool
class_name DataItem
extends Resource

## Base class for all data instances managed by the database system
## Each data type will have a generated subclass of this

## Override in subclasses to return the schema name
func get_type_name() -> String:
	return ""

## Convert instance to Dictionary (for serialization/editing)
func to_dict() -> Dictionary:
	return {}

## Load instance from Dictionary (for deserialization/editing)
func from_dict(data: Dictionary) -> void:
	pass
