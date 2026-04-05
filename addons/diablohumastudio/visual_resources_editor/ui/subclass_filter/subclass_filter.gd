@tool
extends VBoxContainer

var vm: SubclassFilterVM = null


func _on_include_subclasses_check_toggled(pressed: bool) -> void:
	%SubclassWarningLabel.visible = pressed
	if vm:
		vm.set_include_subclasses(pressed)
