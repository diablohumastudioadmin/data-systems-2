@tool
extends DiabloHumaStudioPlugin

## DataManager Sub-Plugin
## Provides CRUD interface for game data types and instances

#const GameDataSystem = preload("res://addons/diablohumastudio/data_manager/game_data_system.gd")
#const DataManagerWindowScene = preload("res://addons/diablohumastudio/data_manager/ui/data_manager_window.tscn")
#
#var game_data_system: GameDataSystem
#var data_manager_window: Window

var tool_bar_name: String = "Data Manager"
var tool_bar_menu: PopupMenu

func _enter_tree() -> void:
	# Initialize game data system
	#game_data_system = GameDataSystem.new()
	_add_tool_bar()

func _add_tool_bar():
	tool_bar_menu = PopupMenu.new()
	if MainToolBarPlugin.instance:
		MainToolBarPlugin.instance.add_toolbar_shubmenu(tool_bar_name, tool_bar_menu)
	else: 
		add_tool_submenu_item(tool_bar_name, tool_bar_menu)

func _remove_tool_bar():
	if MainToolBarPlugin.instance:
		MainToolBarPlugin.instance.remove_toolbar_submenu(tool_bar_name, tool_bar_menu)
	else: 
		remove_tool_menu_item(tool_bar_name)

func move_tool_bar_to_dhs_toolbar():
	pass

func _exit_tree() -> void:
	_remove_tool_bar()
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
