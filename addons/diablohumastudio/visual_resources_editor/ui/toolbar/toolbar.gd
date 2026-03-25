@tool
class_name VREToolbar
extends HBoxContainer

signal refresh_requested
signal error_occurred(message: String)

var _selected_resources: Array[Resource] = []


func set_class_info(class_name_str: String, global_classes_map: Array[Dictionary]) -> void:
	%SaveResourceDialog.current_class_name = class_name_str
	%SaveResourceDialog.global_classes_map = global_classes_map


func update_selection(resources: Array[Resource]) -> void:
	_selected_resources = resources
	var count: int = resources.size()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 else "Delete Selected"


func _on_create_btn_pressed() -> void:
	%SaveResourceDialog.show_create_dialog()


func _on_delete_selected_pressed() -> void:
	if _selected_resources.is_empty():
		return
	var paths: Array[String] = []
	for res: Resource in _selected_resources:
		paths.append(res.resource_path)
	%ConfirmDeleteDialog.show_delete_dialog(paths)


func _on_refresh_btn_pressed() -> void:
	refresh_requested.emit()


func _on_save_dialog_error(message: String) -> void:
	error_occurred.emit(message)


func _on_delete_dialog_error(message: String) -> void:
	error_occurred.emit(message)
