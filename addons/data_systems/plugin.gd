@tool
extends EditorPlugin

## Main Data Systems Plugin
## Manages all subsystems: Master Data, User Data, and Actions

# Preload core classes
const MasterDataSystem = preload("res://addons/data_systems/master_data/master_data_system.gd")

# Preload editor scenes
const DataTypeEditorScene = preload("res://addons/data_systems/master_data/ui/data_type_editor.tscn")
const DataInstanceEditorScene = preload("res://addons/data_systems/master_data/ui/data_instance_editor.tscn")

# Editor windows
var data_type_editor_window: Window
var data_instance_editor_window: Window
var action_editor_window: Window

# Systems (initialized in _enter_tree)
var master_data_system
var user_data_system
var actions_system

# Menu items
var data_menu_item: int = -1


func _enter_tree() -> void:
	print("[Data Systems Plugin] Initializing...")

	# Initialize core systems
	_init_systems()

	# Add menu items
	_add_menu_items()

	# Register keyboard shortcuts
	_register_shortcuts()

	print("[Data Systems Plugin] Initialized successfully")


func _exit_tree() -> void:
	print("[Data Systems Plugin] Shutting down...")

	# Remove menu items
	_remove_menu_items()

	# Close all windows
	_close_all_windows()

	# Cleanup systems
	_cleanup_systems()

	print("[Data Systems Plugin] Shutdown complete")


func _init_systems() -> void:
	"""Initialize all subsystems"""
	# Initialize Master Data System
	master_data_system = MasterDataSystem.new()
	print("[Data Systems Plugin] Master Data System initialized")


func _cleanup_systems() -> void:
	"""Cleanup all subsystems"""
	master_data_system = null
	user_data_system = null
	actions_system = null


func _add_menu_items() -> void:
	"""Add menu items to Window menu"""
	# Add main data editor menu item
	add_tool_submenu_item()
	add_tool_menu_item("Data Type Editor", _on_open_data_type_editor)
	add_tool_menu_item("Data Instance Editor", _on_open_data_instance_editor)
	add_tool_menu_item("Action Editor", _on_open_action_editor)


func _remove_menu_items() -> void:
	"""Remove menu items from Window menu"""
	remove_tool_menu_item("Data Type Editor")
	remove_tool_menu_item("Data Instance Editor")
	remove_tool_menu_item("Action Editor")


func _register_shortcuts() -> void:
	"""Register keyboard shortcuts"""
	# Shortcut will be registered via InputMap in project settings
	# Ctrl+Shift+D to open Data Type Editor
	# This will be implemented more robustly in Phase 7
	pass


func _close_all_windows() -> void:
	"""Close all editor windows"""
	if data_type_editor_window:
		data_type_editor_window.queue_free()
		data_type_editor_window = null

	if data_instance_editor_window:
		data_instance_editor_window.queue_free()
		data_instance_editor_window = null

	if action_editor_window:
		action_editor_window.queue_free()
		action_editor_window = null


# Menu callbacks
func _on_open_data_type_editor() -> void:
	"""Open Data Type Editor window"""
	if data_type_editor_window:
		data_type_editor_window.grab_focus()
		return

	# Create window
	data_type_editor_window = Window.new()
	data_type_editor_window.title = "Data Type Editor"
	data_type_editor_window.size = Vector2i(1000, 700)
	data_type_editor_window.min_size = Vector2i(800, 600)

	# Load editor scene
	var editor = DataTypeEditorScene.instantiate()
	editor.master_data_system = master_data_system
	data_type_editor_window.add_child(editor)

	# Add to editor interface
	get_editor_interface().get_base_control().add_child(data_type_editor_window)
	data_type_editor_window.popup_centered()

	# Cleanup when closed
	data_type_editor_window.close_requested.connect(func():
		data_type_editor_window.queue_free()
		data_type_editor_window = null
	)


func _on_open_data_instance_editor() -> void:
	"""Open Data Instance Editor window"""
	if data_instance_editor_window:
		data_instance_editor_window.grab_focus()
		return

	# Create window
	data_instance_editor_window = Window.new()
	data_instance_editor_window.title = "Data Instance Editor"
	data_instance_editor_window.size = Vector2i(1200, 700)
	data_instance_editor_window.min_size = Vector2i(900, 600)

	# Load editor scene
	var editor = DataInstanceEditorScene.instantiate()
	editor.master_data_system = master_data_system
	data_instance_editor_window.add_child(editor)

	# Add to editor interface
	get_editor_interface().get_base_control().add_child(data_instance_editor_window)
	data_instance_editor_window.popup_centered()

	# Cleanup when closed
	data_instance_editor_window.close_requested.connect(func():
		data_instance_editor_window.queue_free()
		data_instance_editor_window = null
	)


func _on_open_action_editor() -> void:
	"""Open Action Editor window"""
	if action_editor_window:
		action_editor_window.grab_focus()
		return

	# Will be implemented in Phase 5
	print("[Data Systems] Action Editor - Not yet implemented")
	_show_placeholder_window("Action Editor", "action_editor_window")


func _show_placeholder_window(title: String, window_var_name: String) -> void:
	"""Create a placeholder window for testing"""
	var window = Window.new()
	window.title = title
	window.size = Vector2i(800, 600)
	window.min_size = Vector2i(600, 400)

	# Create simple UI
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	window.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	var label = Label.new()
	label.text = "%s\n\nThis editor will be implemented in upcoming phases.\nThe plugin structure is ready!" % title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(window.queue_free)
	vbox.add_child(close_btn)

	# Add to editor
	get_editor_interface().get_base_control().add_child(window)
	window.popup_centered()

	# Store reference
	match window_var_name:
		"data_type_editor_window":
			data_type_editor_window = window
		"data_instance_editor_window":
			data_instance_editor_window = window
		"action_editor_window":
			action_editor_window = window

	# Cleanup when closed
	window.close_requested.connect(func():
		window.queue_free()
		match window_var_name:
			"data_type_editor_window":
				data_type_editor_window = null
			"data_instance_editor_window":
				data_instance_editor_window = null
			"action_editor_window":
				action_editor_window = null
	)


func _handles(object: Object) -> bool:
	# Custom object handling will be added later for Resource types
	return false


func _edit(object: Object) -> void:
	# Custom editing will be added later
	pass
