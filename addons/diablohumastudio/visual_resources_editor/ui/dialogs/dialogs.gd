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
