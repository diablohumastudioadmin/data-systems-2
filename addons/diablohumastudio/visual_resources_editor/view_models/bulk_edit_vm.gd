@tool
class_name BulkEditVM
extends RefCounted

signal selection_for_edit_changed(resources: Array[Resource], class_script: GDScript, property_list: Array[ResourceProperty], shared_property_list: Array[ResourceProperty])

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.selection_changed.connect(_on_selection_changed)
	_model.resources_replaced.connect(_on_resources_replaced)

func _on_selection_changed(_resources: Array[Resource]) -> void:
	_emit_edit_state()

func _on_resources_replaced(_resources: Array[Resource], _shared_props: Array[ResourceProperty]) -> void:
	_emit_edit_state()

func _emit_edit_state() -> void:
	selection_for_edit_changed.emit(
		_model.session.selected_resources,
		_model.current_class_script,
		_model.current_class_property_list,
		_model.current_shared_property_list
	)

func notify_resources_edited() -> void:
	if _model.session.selected_resources.is_empty():
		return
	_model.notify_resources_edited(_model.session.selected_resources)
