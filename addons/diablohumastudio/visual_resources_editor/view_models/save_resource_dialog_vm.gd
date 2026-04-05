@tool
class_name SaveResourceDialogVM
extends RefCounted

signal class_to_create_changed(class_name_: String)
signal show_requested()

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.session.selected_class_changed.connect(func(class_name_: String): class_to_create_changed.emit(class_name_))
	_model.create_new_resource_requested.connect(func(): show_requested.emit())

func get_class_to_create() -> String:
	return _model.session.selected_class

func get_class_script_path(class_name_: String) -> String:
	for entry: Dictionary in _model.global_class_map:
		if entry.get("class", "") == class_name_:
			return entry.get("path", "")
	return ""

func report_error(message: String) -> void:
	_model.report_error(message)
