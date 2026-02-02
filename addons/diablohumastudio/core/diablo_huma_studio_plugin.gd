@tool
@abstract
class_name DiabloHumaStudioPlugin
extends EditorPlugin

var tool_bar_name: String = ""
var tool_bar_menu: PopupMenu

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
	remove_tool_menu_item(tool_bar_name) 
	tool_bar_menu = PopupMenu.new()
	MainToolBarPlugin.instance.add_toolbar_shubmenu(tool_bar_name, tool_bar_menu)
	print("[DiabloHumaStudioPlugin] Moved to Diablo Huma Toolbar")

func move_tool_bar_to_editor_toolbar():
	MainToolBarPlugin.instance.remove_toolbar_submenu(tool_bar_name, tool_bar_menu)
	tool_bar_menu = PopupMenu.new()
	add_tool_submenu_item(tool_bar_name, tool_bar_menu) 
	print("[DiabloHumaStudioPlugin] Moved to Editor Toolbar")
