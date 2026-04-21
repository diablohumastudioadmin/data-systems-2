@tool
extends DiabloHumaStudioPlugin

const TOOLBAR_MENU_NAME: String = "ScenesAndResourcesResaver"

func _enter_tree() -> void:
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu := DH_ScenesAndResourcesResaverToolbar.new()
	DH_MainToolbarPlugin.add_toolbar_submenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)

func _exit_tree() -> void:
	DH_MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
