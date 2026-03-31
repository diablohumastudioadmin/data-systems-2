@tool
class_name VisualResourcesEditorWindow
extends Window

var error_dialog: ErrorDialog


func create_and_add_dialogs() -> void:
	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)


func connect_components() -> void:
	var state: VREStateManager = %VREStateManager

	# Children wire themselves to state
	%ClassSelector.state_manager = state
	%SubclassFilter.state_manager = state
	%ResourceList.state_manager = state
	%Toolbar.state_manager = state
	%BulkEditor.state_manager = state
	%PaginationBar.initialize(state)
	%StatusLabel.initialize(state)

	state.error_occurred.connect(error_dialog.show_error)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	queue_free()
