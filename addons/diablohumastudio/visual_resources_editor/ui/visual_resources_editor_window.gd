@tool
class_name VisualResourcesEditorWindow
extends Window

var _resource_repo: ResourceRepository
var _resource_list_vm: ResourceListVM


func _ready() -> void:
	_resource_repo = ResourceRepository.new()
	_resource_list_vm = ResourceListVM.new(_resource_repo)

	%ClassSelector.vm = ClassSelectorVM.new(_resource_repo)
	%SubclassFilter.vm = SubclassFilterVM.new(_resource_repo)
	%ResourceList.vm = _resource_list_vm

	%Dialogs.save_dialog_vm = SaveResourceDialogVM.new(_resource_repo, %ResourceList.toolbar_vm)
	%Dialogs.confirm_delete_vm = ConfirmDeleteDialogVM.new(_resource_repo)
	%Dialogs.error_dialog_vm = ErrorDialogVM.new(_resource_repo)

	_resource_repo.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_resource_repo.stop()
	queue_free()
