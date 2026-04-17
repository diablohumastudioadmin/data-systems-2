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
	return _model.class_registry.get_script_path(class_name_)

func create_resource(class_name_: String, path: String) -> void:
	var script: GDScript = _model.class_registry.get_class_script(class_name_)
	_model.resource_repo.create(script, path)
