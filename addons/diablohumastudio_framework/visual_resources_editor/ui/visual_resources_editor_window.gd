@tool
class_name DH_VRE_Window
extends Window

var _resource_repo: DH_VRE_ResourceRepository


func _ready() -> void:
	_resource_repo = DH_VRE_ResourceRepository.new()

	%ClassSelector.vm = DH_VRE_ClassSelectorVM.new(_resource_repo)
	%SubclassFilter.vm = DH_VRE_SubclassFilterVM.new(_resource_repo)
	%ResourceList.vm = DH_VRE_ResourceListVM.new(_resource_repo)

	%Dialogs.save_dialog_vm = DH_VRE_SaveResourceDialogVM.new(_resource_repo, %ResourceList.toolbar_vm)
	%Dialogs.confirm_delete_vm = DH_VRE_ConfirmDeleteDialogVM.new(_resource_repo)
	%Dialogs.error_dialog_vm = DH_VRE_ErrorDialogVM.new(_resource_repo)

	_resource_repo.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_resource_repo.stop()
	queue_free()
