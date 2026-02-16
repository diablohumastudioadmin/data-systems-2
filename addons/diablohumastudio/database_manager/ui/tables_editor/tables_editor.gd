@tool
extends Control

## Visual editor for creating and editing table schemas

signal table_selected(type_name: String)
signal table_saved(type_name: String)

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

var database_system: DatabaseSystem
var current_type_name: String = ""
var property_rows: Array = []  # Array of PropertyEditorRow nodes


func _ready() -> void:
	if !database_system:
		database_system = DatabaseSystem.new()

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
	var type_names = database_system.get_table_names()
	for type_name in type_names:
		type_list.add_item(type_name)


func _on_type_list_item_selected(index: int) -> void:
	var type_name = type_list.get_item_text(index)
	_load_type(type_name)


func _load_type(type_name: String) -> void:
	current_type_name = type_name
	type_name_edit.text = type_name
	type_name_edit.editable = false
	_clear_properties()

	# Read schema from generated script, convert Variant.Type to PropertyType
	var properties = database_system.get_type_properties(type_name)
	for prop in properties:
		var prop_type = ResourceGenerator.variant_type_to_property_type(prop)
		_add_property_row(prop.name, prop_type, prop.default)

	table_selected.emit(type_name)


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


func _add_property_row(prop_name: String = "", prop_type: ResourceGenerator.PropertyType = ResourceGenerator.PropertyType.STRING, default_value: Variant = null) -> void:
	var row = preload("uid://ddwwxemdroyaa").new()
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

	# Collect properties from UI rows
	var properties: Array[Dictionary] = []
	for row in property_rows:
		var prop_data = row.get_property_data()
		if prop_data.is_empty():
			continue
		properties.append(prop_data)

	var success = false
	if current_type_name.is_empty():
		success = database_system.add_type(type_name, properties)
	else:
		success = database_system.update_type(type_name, properties)

	if success:
		print("[TablesEditor] Saved table: %s" % type_name)
		current_type_name = type_name
		_refresh_type_list()
		table_saved.emit(type_name)
	else:
		_show_error("Failed to save table")


func _on_delete_type_pressed() -> void:
	if current_type_name.is_empty():
		return

	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Delete table '%s'?\nThis cannot be undone." % current_type_name
	confirm.confirmed.connect(func():
		var success = database_system.remove_type(current_type_name)
		if success:
			print("[TablesEditor] Deleted table: %s" % current_type_name)
			_clear_editor()
			_refresh_type_list()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())

	add_child(confirm)
	confirm.popup_centered()


func _on_type_name_changed(new_text: String) -> void:
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
