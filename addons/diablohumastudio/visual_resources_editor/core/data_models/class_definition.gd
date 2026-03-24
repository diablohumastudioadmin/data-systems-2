@tool
class_name ClassDefinition
extends RefCounted

var class_name_str: String
var script_path: String
var properties: Array[ResourceProperty] = []


func _init(
	p_class_name_str: String = "", p_script_path: String = "",
	p_properties: Array[ResourceProperty] = []
) -> void:
	class_name_str = p_class_name_str
	script_path = p_script_path
	properties = p_properties


func get_script_resource() -> GDScript:
	if script_path.is_empty():
		return null
	return load(script_path)
