@tool
class_name ConfirmDeleteDialogVM
extends RefCounted

signal pending_deletions_changed(paths: Array[String])

var _model: VREModel
var _pending_deletions: Array[String] = []

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.delete_selected_requested.connect(_on_delete_requested)

func _on_delete_requested(paths: Array[String]) -> void:
	_pending_deletions = paths
	pending_deletions_changed.emit(paths)

func get_pending_deletions() -> Array[String]:
	return _pending_deletions

func report_error(message: String) -> void:
	_model.report_error(message)
