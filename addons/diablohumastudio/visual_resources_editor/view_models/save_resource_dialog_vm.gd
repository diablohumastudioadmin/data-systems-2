@tool
class_name SaveResourceDialogVM
extends RefCounted

signal class_to_create_changed(class_name_: String)

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.session.selected_class_changed.connect(func(class_name_: String): class_to_create_changed.emit(class_name_))

func get_class_to_create() -> String:
	return _model.session.selected_class
