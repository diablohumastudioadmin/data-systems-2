@tool
class_name VisualResourcesEditorWindow
extends Window

var _state: VREStateManager


func _ready() -> void:
	_state = VREStateManager.new()
	_state.start()

	%ClassSelector.vm = ClassSelectorVM.new(_state.model)
	%SubclassFilter.vm = SubclassFilterVM.new(_state.model)
	%Toolbar.vm = ToolbarVM.new(_state.model)
	%PaginationBar.vm = PaginationBarVM.new(_state.model)
	%StatusLabel.vm = StatusLabelVM.new(_state.model)
	%Dialogs.save_dialog_vm = SaveResourceDialogVM.new(_state.model)
	%Dialogs.confirm_delete_vm = ConfirmDeleteDialogVM.new(_state.model)
	%Dialogs.error_dialog_vm = ErrorDialogVM.new(_state.model)
	%ResourceList.vm = ResourceListVM.new(_state.model)
	%BulkEditor.model = _state.model


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_state.stop()
	queue_free()
