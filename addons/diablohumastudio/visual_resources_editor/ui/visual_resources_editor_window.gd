@tool
class_name VisualResourcesEditorWindow
extends Window

var _model: VREModel


func _ready() -> void:
	_model = VREModel.new()
	_model.start()

	%ClassSelector.vm = ClassSelectorVM.new(_model)
	%SubclassFilter.vm = SubclassFilterVM.new(_model)
	%Toolbar.vm = ToolbarVM.new(_model)
	%Dialogs.save_dialog_vm = SaveResourceDialogVM.new(_model)
	%Dialogs.confirm_delete_vm = ConfirmDeleteDialogVM.new(_model)
	%Dialogs.error_dialog_vm = ErrorDialogVM.new(_model)
	%ResourceList.vm = ResourceListVM.new(_model)
	%ResourceList.pagination_vm = PaginationBarVM.new(_model)
	%ResourceList.status_vm = StatusLabelVM.new(_model)
	%BulkEditor.model = _model


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_model.stop()
	queue_free()
