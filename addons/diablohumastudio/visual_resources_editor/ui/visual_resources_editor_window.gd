@tool
class_name VisualResourcesEditorWindow
extends Window

var error_dialog: ErrorDialog


func create_and_add_dialogs() -> void:
	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)


func initialize(state: VREStateManager) -> void:
	# Children wire themselves to state
	%ClassSelector.initialize(state)
	%ResourceList.initialize(state)
	%Toolbar.initialize(state)
	%BulkEditor.initialize(state)
	%PaginationBar.initialize(state)
	%StatusLabel.initialize(state)

	# Error dialogs
	%Toolbar.error_occurred.connect(error_dialog.show_error)
	%BulkEditor.error_occurred.connect(error_dialog.show_error)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	queue_free()
