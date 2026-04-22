@tool
extends EditorPlugin

const TOOLBAR_MENU_NAME: String = "CustomSceneRunner"
const _CORE_PATH: String = "res://addons/diablohumastudio_framework/core/main_toolbar_plugin/main_toolbar_plugin.gd"

func _enter_tree() -> void:
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu: DH_CustomScenesRunnerToolbar = DH_CustomScenesRunnerToolbar.new()
	if ResourceLoader.exists(_CORE_PATH):
		load(_CORE_PATH).add_toolbar_submenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)
	else:
		add_tool_submenu_item(TOOLBAR_MENU_NAME, tool_bar_menu)

func _exit_tree() -> void:
	if ResourceLoader.exists(_CORE_PATH):
		load(_CORE_PATH).remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
	else:
		remove_tool_menu_item(TOOLBAR_MENU_NAME)
