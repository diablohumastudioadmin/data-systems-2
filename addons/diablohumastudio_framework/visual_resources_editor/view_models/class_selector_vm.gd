@tool
class_name ClassSelectorVM
extends RefCounted

signal browsable_classes_changed(classes: Array[String])
signal selected_class_changed(class_name_: String)

var _resource_repo: ResourceRepository


func _init(p_resource_repo: ResourceRepository) -> void:
	_resource_repo = p_resource_repo
	_resource_repo.class_registry.classes_changed.connect(_on_classes_changed)
	_resource_repo.selected_class_changed.connect(_on_rr_selected_class_changed)


func get_browsable_classes() -> Array[String]:
	return _resource_repo.class_registry.names


func get_selected_class() -> String:
	return _resource_repo.selected_class


func set_selected_class(class_name_: String) -> void:
	_resource_repo.selected_class = class_name_


func _on_classes_changed(_previous: Array[String], current: Array[String]) -> void:
	browsable_classes_changed.emit(current)


func _on_rr_selected_class_changed(class_name_: String) -> void:
	selected_class_changed.emit(class_name_)
