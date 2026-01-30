@tool
extends Control

## Visual editor for creating and editing data type definitions
## Allows designers to define game data and user data types

signal type_selected(type_name: String, is_user_data: bool)

# Note: These @onready vars will be converted to % unique names after scene is created
@onready var type_list: ItemList = $VBox/HBox/TypeList
@onready var editor_panel: Panel = $VBox/HBox/EditorPanel
@onready var editor_vbox: VBoxContainer = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox

@onready var type_name_edit: LineEdit = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/TypeNameBox/TypeNameEdit
@onready var properties_container: VBoxContainer = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/PropertiesScroll/PropertiesContainer
@onready var add_property_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/AddPropertyBtn
@onready var save_type_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/SaveTypeBtn
@onready var delete_type_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/DeleteTypeBtn

@onready var new_type_btn: Button = $VBox/VBoxContainer/TypeListPanel/VBox/HBoxContainer/NewTypeBtn
@onready var refresh_btn: Button = $VBox/VBoxContainer/TypeListPanel/VBox/HBoxContainer/RefreshBtn

var game_data_system: GameDataSystem
var current_type_name: String = ""
var current_is_user_data: bool = false
var property_rows: Array = []  # Array of PropertyEditorRow nodes


func _ready() -> void:
	if !game_data_system:
		game_data_system = GameDataSystem.new()

	_connect_signals()
	_refresh_type_list()


func _connect_signals() -> void:
	type_list.item_selected.connect(_on_type_list_item_selected)
	new_type_btn.pressed.connect(_on_new_type_pressed)
	refresh_btn.pressed.connect(_refresh_type_list)
	add_property_btn.pressed.connect(_on_add_property_pressed)
	save_type_btn.pressed.connect(_on_save_type_pressed)
	delete_type_btn.pressed.connect(_on_delete_type_pressed)
	type_name_edit.text_changed.connect(_on_type_name_changed)


func _refresh_type_list() -> void:
	type_list.clear()

	# Show all types (game + user) in single list
	var game_type_names = game_data_system.type_registry.get_game_type_names()
	var user_type_names = game_data_system.type_registry.get_user_type_names()

	# Add game types
	for type_name in game_type_names:
		type_list.add_item("[Game] " + type_name)

	# Add user types
	for type_name in user_type_names:
		type_list.add_item("[User] " + type_name)


func _on_type_list_item_selected(index: int) -> void:
	var display_text = type_list.get_item_text(index)

	# Parse type name and category
	if display_text.begins_with("[Game] "):
		current_is_user_data = false
		var type_name = display_text.substr(7)  # Remove "[Game] " prefix
		_load_type(type_name)
	elif display_text.begins_with("[User] "):
		current_is_user_data = true
		var type_name = display_text.substr(7)  # Remove "[User] " prefix
		_load_type(type_name)


func _load_type(type_name: String) -> void:
	current_type_name = type_name

	var type_def = game_data_system.type_registry.get_type(type_name, current_is_user_data)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return

	# Set type name
	type_name_edit.text = type_name
	type_name_edit.editable = false  # Can't rename existing types

	# Clear existing property rows
	_clear_properties()

	# Add property rows
	for prop in type_def.properties:
		_add_property_row(prop.name, prop.type, prop.default)

	type_selected.emit(type_name, current_is_user_data)


func _clear_editor() -> void:
	current_type_name = ""
	type_name_edit.text = ""
	type_name_edit.editable = true
	_clear_properties()


func _clear_properties() -> void:
	for row in property_rows:
		row.queue_free()
	property_rows.clear()


func _on_new_type_pressed() -> void:
	_clear_editor()
	type_list.deselect_all()


func _add_property_row(prop_name: String = "", prop_type: DataTypeDefinition.PropertyType = DataTypeDefinition.PropertyType.STRING, default_value: Variant = null) -> void:
	var row = preload("res://addons/diablohumastudio/data_manager/ui/property_editor_row.gd").new()
	row.set_property(prop_name, prop_type, default_value)
	row.remove_requested.connect(_on_property_remove_requested.bind(row))

	properties_container.add_child(row)
	property_rows.append(row)


func _on_add_property_pressed() -> void:
	_add_property_row()


func _on_property_remove_requested(row: Node) -> void:
	property_rows.erase(row)
	row.queue_free()


func _on_save_type_pressed() -> void:
	var type_name = type_name_edit.text.strip_edges()

	if type_name.is_empty():
		_show_error("Type name cannot be empty")
		return

	# Create type definition
	var definition = DataTypeDefinition.new(type_name, current_is_user_data)

	# Add properties
	for row in property_rows:
		var prop_data = row.get_property_data()
		if prop_data.is_empty():
			continue

		definition.add_property(
			prop_data.name,
			prop_data.type,
			prop_data.default
		)

	# Save to registry
	var success = false
	if current_type_name.is_empty():
		# New type
		success = game_data_system.type_registry.add_type(definition)
	else:
		# Update existing type
		success = game_data_system.type_registry.update_type(definition)

	if success:
		print("[DataTypeTab] Saved type: %s" % type_name)
		current_type_name = type_name
		_refresh_type_list()
		_show_success("Type saved successfully!")
	else:
		_show_error("Failed to save type")


func _on_delete_type_pressed() -> void:
	if current_type_name.is_empty():
		return

	# Confirm deletion
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Delete type '%s'?\nThis cannot be undone." % current_type_name
	confirm.confirmed.connect(func():
		var success = game_data_system.type_registry.remove_type(current_type_name, current_is_user_data)
		if success:
			print("[DataTypeTab] Deleted type: %s" % current_type_name)
			_clear_editor()
			_refresh_type_list()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())

	add_child(confirm)
	confirm.popup_centered()


func _on_type_name_changed(new_text: String) -> void:
	# Enable/disable save button
	save_type_btn.disabled = new_text.strip_edges().is_empty()


func _show_error(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Error"
	dialog.confirmed.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _show_success(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Success"
	dialog.confirmed.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
