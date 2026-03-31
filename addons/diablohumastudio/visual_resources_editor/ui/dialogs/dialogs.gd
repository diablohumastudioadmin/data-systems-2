@tool
class_name Dialogs
extends Control

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	%ConfirmDeleteDialog.state_manager = state_manager
	%SaveResourceDialog.state_manager = state_manager
	state_manager.create_new_resource_requested.connect(on_state_manager_create_new_resource_requested)

func on_state_manager_create_new_resource_requested():
	%SaveResourceDialog.current_class_name = state_manager.current_class_name
	%SaveResourceDialog.global_class_map = state_manager.global_class_map
	%SaveResourceDialog.show_create_dialog()

func on_state_manager_error_occurred(message: String):
	%ErrorDialog.show_error(message)
