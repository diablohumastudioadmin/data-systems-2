@tool
class_name ErrorDialog
extends AcceptDialog

var vm: ErrorDialogVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.error_occurred.connect(_on_error_occurred)


func _on_error_occurred(message: String) -> void:
	dialog_text = message
	popup_centered()
