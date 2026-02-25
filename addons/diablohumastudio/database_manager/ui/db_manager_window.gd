@tool
extends Window

## Combined Data Manager window with tabs for tables and instances

var database_manager: DatabaseManager

func _ready() -> void:
	close_requested.connect(_on_close_requested)

	await get_tree().process_frame

	# database_manager is null when editing the scene in the editor
	if not database_manager:
		return

	%TablesEditor.database_manager = database_manager
	%DataInstanceEditor.database_manager = database_manager

	# When a table is saved/deleted, refresh the instance editor
	%TablesEditor.table_saved.connect(_on_table_changed)
	database_manager.tables_changed.connect(_on_table_changed)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and event.keycode == KEY_ESCAPE:
		_on_close_requested()


func _on_table_changed(_table_name: Variant = null) -> void:
	%DataInstanceEditor.reload()

func _on_close_requested() -> void:
	if %DataInstanceEditor.has_unsaved_changes():
		var dialog := ConfirmationDialog.new()
		dialog.title = "Unsaved Changes"
		dialog.dialog_text = "You have unsaved changes.\nSave before closing?"
		dialog.ok_button_text = "Save & Close"
		dialog.cancel_button_text = "Discard"
		dialog.confirmed.connect(func():
			%DataInstanceEditor.save_all()
			dialog.queue_free()
			_close_with_violation_check()
		)
		dialog.canceled.connect(func():
			%DataInstanceEditor.discard_changes()
			dialog.queue_free()
			queue_free()
		)
		add_child(dialog)
		dialog.popup_centered()
		return

	_close_with_violation_check()


func _close_with_violation_check() -> void:
	var violations: String = %DataInstanceEditor.get_all_required_violations()
	if violations.is_empty():
		queue_free()
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Required Fields Empty"
	dialog.dialog_text = "The following instances have empty required fields and will be deleted:\n\n%s\n\nClose anyway?" % violations
	dialog.confirmed.connect(func():
		%DataInstanceEditor.delete_violating_instances()
		dialog.queue_free()
		queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
