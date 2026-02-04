@tool
extends DiabloHumaStudioPlugin

## DataManager Sub-Plugin
## Provides CRUD interface for game data types and instances

const TOOLBAR_MENU_NAME: String = "DataManager"
#const GameDataSystem = preload("res://addons/diablohumastudio/data_manager/game_data_system.gd")
#const DataManagerWindowScene = preload("res://addons/diablohumastudio/data_manager/ui/data_manager_window.tscn")
#
#var game_data_system: GameDataSystem
#var data_manager_window: Window

func _enter_tree() -> void:
	# Initialize game data system
	#game_data_system = GameDataSystem.new()
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu := DiablohumaStudioToolMenu.new()
	tool_bar_menu.add_item("Launch Data Manager", 1, KEY_F10)
	MainToolbarPlugin.add_toolbar_shubmenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)

func _exit_tree() -> void:
	MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
	## Close window if open
	#if data_manager_window and is_instance_valid(data_manager_window):
		#data_manager_window.queue_free()
		#data_manager_window = null
#
	#game_data_system = null
	#print("[DataManager] Plugin shut down")
#
#
### Opens the Data Manager window
### Called by parent plugin when menu item is selected
#func open_data_manager_window() -> void:
	## If window already exists, just focus it
	#if data_manager_window and is_instance_valid(data_manager_window):
		#data_manager_window.grab_focus()
		#return
#
	## Create new window
	#data_manager_window = DataManagerWindowScene.instantiate()
	#data_manager_window.game_data_system = game_data_system
#
	## Add to editor
	#EditorInterface.get_base_control().add_child(data_manager_window)
#
	## Show window
	#data_manager_window.popup_centered(Vector2i(1200, 800))
#
	#print("[DataManager] Window opened")
