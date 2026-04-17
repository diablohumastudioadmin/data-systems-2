@tool
class_name ClassSelectorVM
extends RefCounted

signal browsable_classes_changed(classes: Array[String])
signal selected_class_changed(class_name_: String)

var _session: SessionStateModel
var _class_registry: ClassRegistry
var _selected_class_script_path: String = ""


func _init(p_session: SessionStateModel, p_class_registry: ClassRegistry) -> void:
	_session = p_session
	_class_registry = p_class_registry
	_class_registry.classes_changed.connect(_on_classes_changed)
	_session.selected_class_changed.connect(_on_session_selected_class_changed)
	_selected_class_script_path = _class_registry.get_script_path(_session.selected_class)


func get_browsable_classes() -> Array[String]:
	return _class_registry.global_class_name_list


func get_selected_class() -> String:
	return _session.selected_class


func set_selected_class(class_name_: String) -> void:
	_session.selected_class = class_name_


func _on_classes_changed(_previous: Array[String], current: Array[String]) -> void:
	browsable_classes_changed.emit(current)
	if _session.selected_class.is_empty():
		return
	if current.has(_session.selected_class):
		_selected_class_script_path = _class_registry.get_script_path(_session.selected_class)
		return
	var new_name: String = _class_registry.detect_rename(_selected_class_script_path)
	_session.selected_class = new_name


func _on_session_selected_class_changed(class_name_: String) -> void:
	_selected_class_script_path = _class_registry.get_script_path(class_name_)
	selected_class_changed.emit(class_name_)
