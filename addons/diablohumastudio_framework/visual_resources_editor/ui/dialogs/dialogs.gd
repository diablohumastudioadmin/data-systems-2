@tool
class_name DH_VRE_Dialogs
extends Control

var save_dialog_vm: DH_VRE_SaveResourceDialogVM = null:
	set(value):
		save_dialog_vm = value
		if is_node_ready():
			%DH_VRE_SaveResourceDialog.vm = save_dialog_vm

var confirm_delete_vm: DH_VRE_ConfirmDeleteDialogVM = null:
	set(value):
		confirm_delete_vm = value
		if is_node_ready():
			%DH_VRE_ConfirmDeleteDialog.vm = confirm_delete_vm

var error_dialog_vm: DH_VRE_ErrorDialogVM = null:
	set(value):
		error_dialog_vm = value
		if is_node_ready():
			%DH_VRE_ErrorDialog.vm = error_dialog_vm


func _ready() -> void:
	if save_dialog_vm:
		%DH_VRE_SaveResourceDialog.vm = save_dialog_vm
	if confirm_delete_vm:
		%DH_VRE_ConfirmDeleteDialog.vm = confirm_delete_vm
	if error_dialog_vm:
		%DH_VRE_ErrorDialog.vm = error_dialog_vm
