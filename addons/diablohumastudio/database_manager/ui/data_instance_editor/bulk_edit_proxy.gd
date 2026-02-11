@tool
class_name BulkEditProxy
extends Resource

## Temporary Resource that exposes a single property to the Godot Inspector.
## Used for bulk-editing: the Inspector shows one field, and changes are
## propagated to all selected DataItem instances.

signal value_changed(property_name: String, new_value: Variant)

var _property_name: String = ""
var _variant_type: int = TYPE_STRING
var _hint: int = PROPERTY_HINT_NONE
var _hint_string: String = ""
var _value: Variant


## Map DataTypeDefinition.PropertyType enum values -> Godot Variant.Type
const PROP_TYPE_TO_VARIANT: Dictionary = {
	0:  TYPE_INT,          # INT
	1:  TYPE_FLOAT,        # FLOAT
	2:  TYPE_STRING,       # STRING
	3:  TYPE_BOOL,         # BOOL
	4:  TYPE_OBJECT,       # TEXTURE2D
	5:  TYPE_VECTOR2,      # VECTOR2
	6:  TYPE_VECTOR3,      # VECTOR3
	7:  TYPE_COLOR,        # COLOR
	8:  TYPE_ARRAY,        # ARRAY
	9:  TYPE_DICTIONARY,   # DICTIONARY
}


## Configure the proxy for a specific property
func setup(prop_name: String, prop_type_enum: int, initial_value: Variant) -> void:
	_property_name = prop_name
	_value = initial_value
	_variant_type = PROP_TYPE_TO_VARIANT.get(prop_type_enum, TYPE_STRING)

	# Special hints for resource types
	_hint = PROPERTY_HINT_NONE
	_hint_string = ""
	if prop_type_enum == 4:  # TEXTURE2D
		_hint = PROPERTY_HINT_RESOURCE_TYPE
		_hint_string = "Texture2D"

	notify_property_list_changed()


## Dynamic property list — exposes exactly one property to the Inspector
func _get_property_list() -> Array[Dictionary]:
	if _property_name.is_empty():
		return []
	return [{
		"name": _property_name,
		"type": _variant_type,
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR,
		"hint": _hint,
		"hint_string": _hint_string,
	}]


func _get(property: StringName) -> Variant:
	if property == _property_name:
		return _value
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == _property_name:
		_value = value
		value_changed.emit(str(_property_name), value)
		return true
	return false
