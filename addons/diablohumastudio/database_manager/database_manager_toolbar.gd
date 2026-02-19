@tool
class_name DataManagerToolbar
extends DiablohumaStudioToolMenu

var database_manager: DatabaseManager
const DataManagerWindowPksc = preload("uid://dwdqpra1ov4q6")
var data_manager_window: Window

func _enter_tree() -> void:
	clear()
	database_manager = DatabaseManager.new()
	database_manager.name = "EditorDatabaseManager"
	add_child(database_manager)
	add_item("Launch Data Manager", 0, KEY_F10)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	if data_manager_window and is_instance_valid(data_manager_window):
		data_manager_window.queue_free()
		data_manager_window = null
	if database_manager and is_instance_valid(database_manager):
		database_manager.queue_free()
		database_manager = null

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
	data_manager_window.database_manager = database_manager

	EditorInterface.get_base_control().add_child(data_manager_window)
	data_manager_window.popup_centered(Vector2i(1200, 800))
