@tool
class_name VREToolbar
extends HBoxContainer

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	state_manager.selection_changed.connect(update_selection)
	state_manager.resources_replaced.connect(func(_resources: Array[Resource], _props: Array[ResourceProperty]) -> void:
		%SaveResourceDialog.current_class_name = state_manager.current_class_name
		%SaveResourceDialog.global_class_map = state_manager.global_class_map
	)


func update_selection(resources: Array[Resource]) -> void:
	var count: int = resources.size()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 else "Delete Selected"


func _on_create_btn_pressed() -> void:
	%SaveResourceDialog.show_create_dialog()


func _on_delete_selected_pressed() -> void:
	if state_manager.selected_resources.is_empty():
		return
	var paths: Array[String] = []
	for res: Resource in state_manager.selected_resources:
		paths.append(res.resource_path)
	%ConfirmDeleteDialog.show_delete_dialog(paths)


func _on_refresh_btn_pressed() -> void:
	state_manager.refresh_resource_list_values()


func _on_save_dialog_error(message: String) -> void:
	state_manager.report_error(message)


func _on_delete_dialog_error(message: String) -> void:
	state_manager.report_error(message)
