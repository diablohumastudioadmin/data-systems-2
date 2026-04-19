@tool
class_name ClassSelectorVM
extends RefCounted

signal browsable_classes_changed(classes: Array[String])
signal selected_class_changed(class_name_: String)

var _resource_repo: ResourceRepository
var _selected_class_script_path: String = ""


func _init(p_resource_repo: ResourceRepository) -> void:
	_resource_repo = p_resource_repo
	_resource_repo.class_registry.classes_changed.connect(_on_classes_changed)
	_resource_repo.selected_class_changed.connect(_on_rr_selected_class_changed)
	_selected_class_script_path = _resource_repo.class_registry.get_script_path(_resource_repo.selected_class)


func get_browsable_classes() -> Array[String]:
	return _resource_repo.class_registry.global_class_name_list


func get_selected_class() -> String:
	return _resource_repo.selected_class


func set_selected_class(class_name_: String) -> void:
	_resource_repo.selected_class = class_name_


func _on_classes_changed(_previous: Array[String], current: Array[String]) -> void:
	browsable_classes_changed.emit(current)
	if _resource_repo.selected_class.is_empty():
		return
	if current.has(_resource_repo.selected_class):
		_selected_class_script_path = _resource_repo.class_registry.get_script_path(_resource_repo.selected_class)
		return
	var new_name: String = _resource_repo.class_registry.detect_rename(_selected_class_script_path)
	_resource_repo.selected_class = new_name


func _on_rr_selected_class_changed(class_name_: String) -> void:
	_selected_class_script_path = _resource_repo.class_registry.get_script_path(class_name_)
	selected_class_changed.emit(class_name_)
