@tool
class_name VREGBulkEditProxy
extends Resource

signal property_value_changed(property_name: String, new_value: Variant)

var _target_class_name: String = ""
var _properties: Array[Dictionary] = []
var _values: Dictionary = {}

func setup(target_class_name: String, script_path: String) -> void:
	_target_class_name = target_class_name
	
	var inst: Resource
	if script_path != "":
		var script = load(script_path)
		if script:
			inst = script.new()
	elif ClassDB.class_exists(target_class_name):
		inst = ClassDB.instantiate(target_class_name)
		
	if inst:
		var props = inst.get_property_list()
		for p in props:
			if (p.usage & PROPERTY_USAGE_EDITOR) and not p.name in ["resource_path", "resource_name", "resource_local_to_scene", "script"]:
				_properties.append(p)
				_values[p.name] = inst.get(p.name)
		# inst is a RefCounted, so it frees automatically when out of scope.
		
	notify_property_list_changed()

func _get_property_list() -> Array[Dictionary]:
	return _properties

func _get(property: StringName) -> Variant:
	if _values.has(property):
		return _values[property]
	return null

func _set(property: StringName, value: Variant) -> bool:
	if _values.has(property):
		_values[property] = value
		property_value_changed.emit(str(property), value)
		return true
	return false
