@tool
extends DiabloHumaStudioPlugin

const TOOLBAR_MENU_NAME: String = "CustomSceneRunner"

func _enter_tree() -> void:
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu := CustomScenesRunnerToolbar.new()
	MainToolbarPlugin.add_toolbar_shubmenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)

func _exit_tree() -> void:
	MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
