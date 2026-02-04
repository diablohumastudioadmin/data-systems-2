@tool
class_name DataManagerToolbar
extends DiablohumaStudioToolMenu

var game_data_system: GameDataSystem
const DataManagerWindowPksc = preload("uid://dwdqpra1ov4q6")
var data_manager_window: Window

func _enter_tree() -> void:
	print("enter data toolbar")
	clear()
	game_data_system = GameDataSystem.new()
	add_item("Launch Data Manager", 0, KEY_F10)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	if data_manager_window and is_instance_valid(data_manager_window):
		data_manager_window.queue_free()
		data_manager_window = null
	game_data_system = null

func _on_menu_id_pressed(id: int):
	print(id)
	match id:
		0:
			open_data_manager_window()

func open_data_manager_window() -> void:
	print("sss")
	if data_manager_window and is_instance_valid(data_manager_window):
		data_manager_window.grab_focus()
		return

	data_manager_window = DataManagerWindowPksc.instantiate()
	data_manager_window.game_data_system = game_data_system

	EditorInterface.get_base_control().add_child(data_manager_window)
	data_manager_window.popup_centered(Vector2i(1200, 800))
