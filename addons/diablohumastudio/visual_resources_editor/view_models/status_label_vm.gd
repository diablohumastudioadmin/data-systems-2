@tool
class_name StatusLabelVM
extends RefCounted

signal counts_updated(visible_count: int, selected_count: int)

var _model: VREModel
var _visible_count: int = 0

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.resources_replaced.connect(_on_resources_replaced)
	_model.resources_added.connect(_on_resources_added)
	_model.resources_removed.connect(_on_resources_removed)
	_model.selection_changed.connect(_on_selection_changed)

func _on_resources_replaced(resources: Array[Resource], _shared_props: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	counts_updated.emit(_visible_count, _model.session.selected_resources.size())

func _on_resources_added(resources: Array[Resource]) -> void:
	_visible_count += resources.size()
	counts_updated.emit(_visible_count, _model.session.selected_resources.size())

func _on_resources_removed(resources: Array[Resource]) -> void:
	_visible_count -= resources.size()
	counts_updated.emit(_visible_count, _model.session.selected_resources.size())

func _on_selection_changed(resources: Array[Resource]) -> void:
	counts_updated.emit(_visible_count, resources.size())

func get_visible_count() -> int:
	return _visible_count

func get_selected_count() -> int:
	return _model.session.selected_resources.size()
