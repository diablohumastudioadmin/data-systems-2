@tool
class_name MainToolBarPlugin
extends EditorPlugin

var _diablo_huma_toolbar_menu: PopupMenu

func _enter_tree() -> void:
	_add_diablo_huma_toolbar_menu()

func _exit_tree() -> void:
	remove_tool_menu_item("DiabloHumaStudio")

func _add_diablo_huma_toolbar_menu() -> void:
	_diablo_huma_toolbar_menu = PopupMenu.new()
	_diablo_huma_toolbar_menu.name = "DiabloHumaStudioMenu"
	add_tool_submenu_item("DiabloHumaStudio", _diablo_huma_toolbar_menu)

func add_toolbar_shubmenu(name: String, sub_menu: PopupMenu):
	_diablo_huma_toolbar_menu.add_submenu_node_item(name, sub_menu)
