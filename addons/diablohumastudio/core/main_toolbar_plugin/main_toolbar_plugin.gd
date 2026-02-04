@tool
class_name DiabloHumaMainToolBarPlugin
extends EditorPlugin

var _diablo_huma_toolbar_menu: MainToolBarPopupMenu
var _tool_bar_name: String = "DiabloHumaSuit"

static var instance: DiabloHumaMainToolBarPlugin

func _enter_tree() -> void:
	instance = self
	_add_main_toolbar_menu()
	_relocate_inner_to_diablohuma()

func _exit_tree() -> void:
	_relocate_inner_to_editor()
	remove_tool_menu_item(_tool_bar_name)

func _add_main_toolbar_menu() -> void:
	_diablo_huma_toolbar_menu = MainToolBarPopupMenu.new()
	add_tool_submenu_item(_tool_bar_name, _diablo_huma_toolbar_menu)

func _relocate_inner_to_editor():
	var active_toolbars: Dictionary[String, DiablohumaStudioToolMenu]
	active_toolbars = ToolBarsAndPlugins.get_diablohuma_toolbars_from_toolbar(_diablo_huma_toolbar_menu)
	for key in active_toolbars:
		_move_tool_bar_to_base(key, active_toolbars[key])

func _relocate_inner_to_diablohuma():
	var active_toolbars: Dictionary[String, DiablohumaStudioToolMenu]
	var tool_menu: PopupMenu = ToolBarsAndPlugins.get_editor_tool_bar()
	active_toolbars = ToolBarsAndPlugins.get_diablohuma_toolbars_from_toolbar(tool_menu)
	for key in active_toolbars:
		_move_tool_bar_to_diablohuma(key, active_toolbars[key])

func _move_tool_bar_to_base(name: String, tool_bar: DiablohumaStudioToolMenu):
	var duplicated_tool_bar = ToolBarsAndPlugins.duplicate_menu(tool_bar)
	ToolBarsAndPlugins.remove_item_in_toolbar_by_name(_diablo_huma_toolbar_menu, name)
	add_tool_submenu_item(name, duplicated_tool_bar)

func _move_tool_bar_to_diablohuma(name: String, tool_bar: DiablohumaStudioToolMenu):
	var duplicated_tool_bar = ToolBarsAndPlugins.duplicate_menu(tool_bar)
	remove_tool_menu_item(name)
	_diablo_huma_toolbar_menu.add_submenu_node_item(name, duplicated_tool_bar)

static func add_toolbar_shubmenu(name: String, sub_menu: PopupMenu, plugin: EditorPlugin):
	if instance: instance._diablo_huma_toolbar_menu.add_submenu_node_item(name, sub_menu)
	else: plugin.add_tool_submenu_item(name, sub_menu) 

static func remove_toolbar_submenu(name: String, plugin: EditorPlugin):
	if instance: 	ToolBarsAndPlugins.remove_item_in_toolbar_by_name(instance._diablo_huma_toolbar_menu, name)
	else: plugin.remove_tool_menu_item(name)

class MainToolBarPopupMenu extends PopupMenu:
	pass
