@tool
class_name IClassesRepository
extends RefCounted

signal updated()
signal class_list_changed(classes: Array[String])
signal _property_list_changed()
signal orphaned_resources_found(resources: Array[Resource])

var global_class_map: Array[Dictionary] = []
var class_to_path_map: Dictionary[String, String] = {}
var class_to_parent_map: Dictionary[String, String] = {}
var class_name_list: Array[String] = []

var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var included_class_property_lists: Dictionary = {}
var shared_property_list: Array[ResourceProperty] = []


func rebuild() -> void:
	pass


func get_class_script(class_name_str: String) -> GDScript:
	return null


func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]:
	return []


func scan_properties(base_class: String, included_classes: Array[String]) -> void:
	pass
