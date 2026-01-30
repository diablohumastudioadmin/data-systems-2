@tool
extends Window

## Combined Data Manager window with tabs for types and instances

var game_data_system: GameDataSystem


func _ready() -> void:
	close_requested.connect(_on_close_requested)

	# Wait for children to be ready
	await get_tree().process_frame

	# Pass system reference to tabs
	var data_type_tab = %TabContainer.get_child(0)
	var data_instance_tab = %TabContainer.get_child(1)

	if data_type_tab:
		data_type_tab.game_data_system = game_data_system

	if data_instance_tab:
		data_instance_tab.game_data_system = game_data_system


func _on_close_requested() -> void:
	queue_free()
