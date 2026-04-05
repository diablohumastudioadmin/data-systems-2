@tool
class_name ClassSelectorVM
extends RefCounted

signal browsable_classes_changed(classes: Array[String])
signal selected_class_changed(class_name_: String)

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.project_classes_changed.connect(func(classes: Array[String]): browsable_classes_changed.emit(classes))
	_model.current_class_renamed.connect(func(new_name: String): selected_class_changed.emit(new_name))
	_model.session.selected_class_changed.connect(func(class_name_: String): selected_class_changed.emit(class_name_))

func get_browsable_classes() -> Array[String]:
	return _model.global_class_name_list

func get_selected_class() -> String:
	return _model.session.selected_class

func set_selected_class(class_name_: String) -> void:
	_model.session.selected_class = class_name_
