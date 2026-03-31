@tool
class_name VisualResourcesEditorWindow
extends Window


func _ready() -> void:
	var state: VREStateManager = %VREStateManager

	# Children wire themselves to state
	%ClassSelector.state_manager = state
	%SubclassFilter.state_manager = state
	%ResourceList.state_manager = state
	%Toolbar.state_manager = state
	%BulkEditor.state_manager = state
	%PaginationBar.state_manager = state
	%StatusLabel.state_manager = state
	%Dialogs.state_manager = state

	

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	queue_free()
