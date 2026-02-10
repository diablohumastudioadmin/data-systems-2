@tool
extends Window

## Combined Data Manager window with tabs for types and instances

var game_data_system: GameDataSystem

func _ready() -> void:
	close_requested.connect(_on_close_requested)

	await get_tree().process_frame

	%DataTypeEditor.game_data_system = game_data_system
	%DataInstanceEditor.game_data_system = game_data_system

func _on_close_requested() -> void:
	queue_free()
