@tool
extends VBoxContainer

var state_manager: VREStateManager = null


func _on_include_subclasses_check_toggled(pressed: bool) -> void:
	%SubclassWarningLabel.visible = pressed
	if state_manager:
		state_manager.set_include_subclasses(pressed)
