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

func _on_table_changed(_table_name: Variant = null) -> void:
	%DataInstanceEditor.reload()

func _on_close_requested() -> void:
	queue_free()
