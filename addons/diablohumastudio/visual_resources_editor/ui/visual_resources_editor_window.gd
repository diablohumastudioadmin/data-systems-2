@tool
class_name VisualResourcesEditorWindow
extends Window

var _state: VREStateManager


func _ready() -> void:
	_state = VREStateManager.new()
	_state.start()

	%ClassSelector.state_manager = _state
	%SubclassFilter.state_manager = _state
	%ResourceList.state_manager = _state
	%Toolbar.state_manager = _state
	%BulkEditor.state_manager = _state
	%PaginationBar.state_manager = _state
	%StatusLabel.state_manager = _state
	%Dialogs.state_manager = _state


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_state.stop()
	queue_free()
