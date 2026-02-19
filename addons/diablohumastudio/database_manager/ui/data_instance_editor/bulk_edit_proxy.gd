@tool
class_name BulkEditProxy
extends Resource

## Temporary Resource that exposes a single field to the Godot Inspector.
## Used for bulk-editing: the Inspector shows one field, and changes are
## propagated to all selected DataItem instances.

signal value_changed(field_name: String, new_value: Variant)

var _field_name: String = ""
var _variant_type: int = TYPE_STRING
var _hint: int = PROPERTY_HINT_NONE
var _hint_string: String = ""
var _value: Variant


## Configure the proxy for a specific field.
## variant_type: Godot's native Variant.Type (TYPE_INT, TYPE_STRING, etc.)
func setup(field_name: String, variant_type: int, initial_value: Variant, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	_field_name = field_name
	_value = initial_value
	_variant_type = variant_type
	_hint = hint
	_hint_string = hint_string
	notify_property_list_changed()


## Dynamic property list — exposes exactly one field to the Inspector
func _get_property_list() -> Array[Dictionary]:
	if _field_name.is_empty():
		return []
	return [{
		"name": _field_name,
		"type": _variant_type,
		"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR,
		"hint": _hint,
		"hint_string": _hint_string,
	}]


func _get(property: StringName) -> Variant:
	if property == _field_name:
		return _value
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == _field_name:
		_value = value
		value_changed.emit(str(_field_name), value)
		return true
	return false
