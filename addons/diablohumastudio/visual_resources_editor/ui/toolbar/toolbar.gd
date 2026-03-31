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


func update_selection(resources: Array[Resource]) -> void:
	var count: int = resources.size()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 else "Delete Selected"


func _on_create_btn_pressed() -> void:
	state_manager.request_create_new_resouce()


func _on_delete_selected_pressed() -> void:
	state_manager.request_delete_selected_resources()


func _on_refresh_btn_pressed() -> void:
	state_manager.refresh_resource_list_values()
