@tool
class_name DH_VRE_ResourceProperty
extends RefCounted

var name: String
var type: int = TYPE_NIL
var hint: int = PROPERTY_HINT_NONE
var hint_string: String = ""


func _init(
	p_name: String = "", p_type: int = TYPE_NIL,
	p_hint: int = PROPERTY_HINT_NONE, p_hint_string: String = ""
) -> void:
	name = p_name
	type = p_type
	hint = p_hint
	hint_string = p_hint_string


func equals(other: DH_VRE_ResourceProperty) -> bool:
	return (
		name == other.name
		and type == other.type
		and hint == other.hint
		and hint_string == other.hint_string
	)


static func arrays_equal(a: Array[DH_VRE_ResourceProperty], b: Array[DH_VRE_ResourceProperty]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if not a[i].equals(b[i]):
			return false
	return true
