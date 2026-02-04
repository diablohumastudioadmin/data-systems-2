class_name ToolBarsAndPlugins
extends RefCounted

static func get_editor_tool_bar() -> PopupMenu:
	var base = EditorInterface.get_base_control()
	var project_menu = base.find_child("*Project", true, false)
	var tool_menu_name: String
	var tool_menu: PopupMenu
	for ii in project_menu.item_count:
		if project_menu.get_item_text(ii) == "Tools":
			tool_menu_name = project_menu.get_item_submenu(ii)
			tool_menu = project_menu.get_node(tool_menu_name)
	return tool_menu

static func get_diablohuma_toolbars_from_toolbar(toolbar_: PopupMenu) -> Dictionary[String, DiablohumaStudioToolMenu]:
	var inner_toolbars: Dictionary[String, DiablohumaStudioToolMenu]
	for ii in toolbar_.item_count:
		var item_submenu_name = toolbar_.get_item_submenu(ii)
		if !item_submenu_name: continue
		var active_toolbar: PopupMenu = toolbar_.get_node(item_submenu_name)
		if !active_toolbar is DiablohumaStudioToolMenu: continue
		inner_toolbars[toolbar_.get_item_text(ii)] = active_toolbar as DiablohumaStudioToolMenu
	return inner_toolbars

static func _get_active_diablohuma_plugins() -> Dictionary[String, DiabloHumaStudioPlugin]:
	var active_plugins: Dictionary[String, DiabloHumaStudioPlugin]
	var active_plugin_paths: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled")
	for plugin_path in active_plugin_paths:
		if !plugin_path.begins_with("res://addons/diablohumastudio/"): continue
		var plugins_folder_path: String = plugin_path.get_base_dir()
		var plugin_script_path: String = get_config_value(plugin_path, "plugin", "script")
		var full_path: String = plugins_folder_path.path_join(plugin_script_path)
		var plugin_instance: Node = get_active_plugin_instance_by_path(full_path)
		var plugin_name: String = get_config_value(plugin_path, "plugin", "name")
		if plugin_instance and plugin_instance is DiabloHumaStudioPlugin: 
			active_plugins[plugin_name] = plugin_instance
	return active_plugins

static func get_config_value(path: String, section: String, key: String) -> Variant:
	var plugin_cfg_file:= ConfigFile.new()
	plugin_cfg_file.load(path)
	return plugin_cfg_file.get_value(section, key)

static func get_active_plugin_instance_by_path(script_path: String):
	var editor_root = EditorInterface.get_base_control().get_parent()
	for child in editor_root.get_children():
		if child is EditorPlugin:
			if child.get_script() and child.get_script().resource_path == script_path:
				return child

static func remove_item_in_toolbar_by_name(tool_bar: PopupMenu ,name: String):
	for ii in tool_bar.item_count:
		if tool_bar.get_item_text(ii) == name:
			tool_bar.remove_item(ii)

## Properly duplicate a PopupMenu with all properties including shortcuts
static func duplicate_menu(source: PopupMenu) -> PopupMenu:
	var new_menu = source.duplicate()

	# Clear and rebuild to ensure shortcuts are preserved
	new_menu.clear()

	for i in source.item_count:
		var text = source.get_item_text(i)
		var icon = source.get_item_icon(i)
		var id = source.get_item_id(i)
		var accel = source.get_item_accelerator(i)  # This is the shortcut
		var submenu = source.get_item_submenu(i)

		if submenu:
			# It's a submenu item
			var submenu_node = source.get_node(submenu)
			new_menu.add_submenu_node_item(text, submenu_node)
		else:
			# Regular item
			new_menu.add_item(text, id)
			if icon:
				new_menu.set_item_icon(i, icon)
			if accel != 0:
				new_menu.set_item_accelerator(i, accel)

		# Copy other properties
		new_menu.set_item_disabled(i, source.is_item_disabled(i))
		new_menu.set_item_checked(i, source.is_item_checked(i))
		new_menu.set_item_tooltip(i, source.get_item_tooltip(i))

	return new_menu
