@tool
extends Window

## Combined Data Manager window with tabs for tables and instances

var database_system: DatabaseSystem

func _ready() -> void:
	close_requested.connect(_on_close_requested)

	await get_tree().process_frame

	%TablesEditor.database_system = database_system
	%DataInstanceEditor.database_system = database_system

	# When a table is saved/deleted, refresh the instance editor
	%TablesEditor.table_saved.connect(_on_table_changed)
	database_system.types_changed.connect(_on_table_changed)

func _on_table_changed(_type_name: Variant = null) -> void:
	%DataInstanceEditor.reload()

func _on_close_requested() -> void:
	queue_free()
