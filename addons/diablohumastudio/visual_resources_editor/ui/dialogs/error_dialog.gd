@tool
class_name ErrorDialog
extends AcceptDialog

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()

func _connect_state():
	state_manager.error_occurred.connect(show_error)

func show_error(message: String) -> void:
	dialog_text = message
	popup_centered()
