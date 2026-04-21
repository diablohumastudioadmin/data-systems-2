@tool
extends VBoxContainer

var vm: DH_VRE_SubclassFilterVM = null


func _on_include_subclasses_check_toggled(pressed: bool) -> void:
	%SubclassWarningLabel.visible = pressed
	if vm:
		vm.set_include_subclasses(pressed)
