@tool
class_name VisualResourcesEditorWindow
extends Window

var _session: SessionStateModel
var _resource_repo: ResourceRepository

var _toolbar_vm: ToolbarVM
var _resource_list_vm: ResourceListVM


func _ready() -> void:
	_session = SessionStateModel.new()
	_resource_repo = ResourceRepository.new()

	_resource_list_vm = ResourceListVM.new(_session, _resource_repo)
	_toolbar_vm = ToolbarVM.new(_resource_repo, _resource_list_vm.selection_manager)
	_toolbar_vm.refresh_requested.connect(_resource_list_vm.refresh_current_view)

	var confirm_delete_vm: ConfirmDeleteDialogVM = ConfirmDeleteDialogVM.new(_resource_repo, _toolbar_vm)
	confirm_delete_vm.bind_resource_list(_resource_list_vm)

	%ClassSelector.vm = ClassSelectorVM.new(_resource_repo)
	%SubclassFilter.vm = SubclassFilterVM.new(_resource_repo)
	%Toolbar.vm = _toolbar_vm
	%Dialogs.save_dialog_vm = SaveResourceDialogVM.new(_resource_repo, _toolbar_vm)
	%Dialogs.confirm_delete_vm = confirm_delete_vm
	%Dialogs.error_dialog_vm = ErrorDialogVM.new(_resource_repo)
	%ResourceList.vm = _resource_list_vm
	%BulkEditor.selection_manager = _resource_list_vm.selection_manager
	%BulkEditor.resource_repo = _resource_repo

	_resource_repo.start()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_resource_repo.stop()
	queue_free()
