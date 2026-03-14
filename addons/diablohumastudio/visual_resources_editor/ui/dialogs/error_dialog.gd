@tool
class_name ErrorDialog
extends AcceptDialog


func show_error(message: String) -> void:
	dialog_text = message
	popup_centered()
