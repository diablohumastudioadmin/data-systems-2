@tool
class_name MainToolBarPlugin
extends EditorPlugin

var _diablo_huma_toolbar_menu: PopupMenu
var _tool_bar_name: String = "DiabloHumaStudioMenu"

static var instance: MainToolBarPlugin

func _enter_tree() -> void:
	instance = self
	_add_main_toolbar_menu()
	_relocate_inner_to_diablohuma_tb()

func _exit_tree() -> void:
	_relocate_inner_to_editor_tb()
	remove_tool_menu_item(_tool_bar_name)

func _add_main_toolbar_menu() -> void:
	_diablo_huma_toolbar_menu = PopupMenu.new()
	add_tool_submenu_item(_tool_bar_name, _diablo_huma_toolbar_menu)

func _relocate_inner_to_editor_tb():
	var plugins: Array[DiabloHumaStudioPlugin] = _get_active_diablohuma_plugins()
	for plugin in plugins:
		plugin.move_tool_bar_to_editor_toolbar()

func _relocate_inner_to_diablohuma_tb():
	var plugins: Array[DiabloHumaStudioPlugin] = _get_active_diablohuma_plugins()
	print("relocate to huma")
	for plugin in plugins:
		print(plugin)
		plugin.move_tool_bar_to_dhs_toolbar()
	
func _get_active_diablohuma_plugins() -> Array[DiabloHumaStudioPlugin]:
	var plugins: Array[DiabloHumaStudioPlugin]
	var active_plugins_paths: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled")
	for plugins_path in active_plugins_paths:
		if !plugins_path.begins_with("res://addons/diablohumastudio/"): continue
		var plugins_folder_path: String = plugins_path.get_base_dir()
		var plugin_script_path: String = _get_config_value(plugins_path, "plugin", "script")
		var full_path: String = plugins_folder_path.path_join(plugin_script_path)
		var plugin_instance: Node = _get_active_plugin_instance_by_path(full_path)
		if plugin_instance and plugin_instance is DiabloHumaStudioPlugin: 
			plugins.append(plugin_instance)
	return plugins

func _get_config_value(path: String, section: String, key: String) -> Variant:
	var plugin_cfg_file:= ConfigFile.new()
	plugin_cfg_file.load(path)
	return plugin_cfg_file.get_value(section, key)

func _get_active_plugin_instance_by_path(script_path: String):
	var editor_root = EditorInterface.get_base_control().get_parent()
	for child in editor_root.get_children():
		if child is EditorPlugin:
			if child.get_script() and child.get_script().resource_path == script_path:
				return child

func add_toolbar_item(name: String, callable: Callable):
	_diablo_huma_toolbar_menu.add_item(name)

func remove_toolvar_item(name: String):
	_remove_item_in_dh_by_name(name)

func add_toolbar_shubmenu(name: String, sub_menu: PopupMenu):
	_diablo_huma_toolbar_menu.add_submenu_node_item(name, sub_menu)

func remove_toolbar_submenu(name: String):
	_remove_item_in_dh_by_name(name)

func _remove_item_in_dh_by_name(name: String):
	for ii in _diablo_huma_toolbar_menu.item_count:
		if _diablo_huma_toolbar_menu.get_item_text(ii) == name:
			_diablo_huma_toolbar_menu.remove_item(ii)
