@tool
extends Control

## Visual editor for creating and editing table schemas

signal table_selected(table_name: String)
signal table_saved(table_name: String)

# Note: These @onready vars will be converted to % unique names after scene is created
@onready var table_list: ItemList = $VBox/HBox/TableList
@onready var editor_panel: Panel = $VBox/HBox/EditorPanel
@onready var editor_vbox: VBoxContainer = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox

@onready var table_name_edit: LineEdit = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/TableNameBox/TableNameEdit
@onready var properties_container: VBoxContainer = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/PropertiesScroll/PropertiesContainer
@onready var add_property_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/AddPropertyBtn
@onready var save_table_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/SaveTableBtn
@onready var delete_table_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/DeleteTableBtn

@onready var new_table_btn: Button = $VBox/VBoxContainer/TableListPanel/VBox/HBoxContainer/NewTableBtn
@onready var refresh_btn: Button = $VBox/VBoxContainer/TableListPanel/VBox/HBoxContainer/RefreshBtn

var database_system: DatabaseSystem: set = _set_database_system
var current_table_name: String = ""
var property_rows: Array = []  # Array of PropertyEditorRow nodes
var _initialized: bool = false


func _set_database_system(value: DatabaseSystem) -> void:
	database_system = value
	if value and is_node_ready() and not _initialized:
		_initialize()


func _ready() -> void:
	if not database_system:
		return
	_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_connect_signals()
	_refresh_table_list()


func _connect_signals() -> void:
	table_list.item_selected.connect(_on_table_list_item_selected)
	new_table_btn.pressed.connect(_on_new_table_pressed)
	refresh_btn.pressed.connect(_refresh_table_list)
	add_property_btn.pressed.connect(_on_add_property_pressed)
	save_table_btn.pressed.connect(_on_save_table_pressed)
	delete_table_btn.pressed.connect(_on_delete_table_pressed)
	table_name_edit.text_changed.connect(_on_table_name_changed)


func _refresh_table_list() -> void:
	table_list.clear()
	var table_names = database_system.get_table_names()
	for table_name in table_names:
		table_list.add_item(table_name)


func _on_table_list_item_selected(index: int) -> void:
	var table_name = table_list.get_item_text(index)
	_load_table(table_name)


func _load_table(table_name: String) -> void:
	current_table_name = table_name
	table_name_edit.text = table_name
	table_name_edit.editable = false
	_clear_properties()

	# Read schema from generated script, convert Variant.Type to PropertyType
	var properties = database_system.get_table_properties(table_name)
	for prop in properties:
		var prop_type = ResourceGenerator.variant_type_to_property_type(prop)
		_add_property_row(prop.name, prop_type, prop.default)

	table_selected.emit(table_name)


func _clear_editor() -> void:
	current_table_name = ""
	table_name_edit.text = ""
	table_name_edit.editable = true
	_clear_properties()


func _clear_properties() -> void:
	for row in property_rows:
		row.queue_free()
	property_rows.clear()


func _on_new_table_pressed() -> void:
	_clear_editor()
	table_list.deselect_all()


func _add_property_row(prop_name: String = "", prop_type: ResourceGenerator.PropertyType = ResourceGenerator.PropertyType.STRING, default_value: Variant = null) -> void:
	var row = preload("property_editor_row.tscn").instantiate()
	row.set_property(prop_name, prop_type, default_value)
	row.remove_requested.connect(_on_property_remove_requested.bind(row))

	properties_container.add_child(row)
	property_rows.append(row)


func _on_add_property_pressed() -> void:
	_add_property_row()


func _on_property_remove_requested(row: Node) -> void:
	property_rows.erase(row)
	row.queue_free()


func _on_save_table_pressed() -> void:
	var table_name = table_name_edit.text.strip_edges()

	if table_name.is_empty():
		_show_error("Table name cannot be empty")
		return

	# Collect properties from UI rows
	var properties: Array[Dictionary] = []
	for row in property_rows:
		var prop_data = row.get_property_data()
		if prop_data.is_empty():
			continue
		properties.append(prop_data)

	var success = false
	if current_table_name.is_empty():
		success = database_system.add_table(table_name, properties)
	else:
		success = database_system.update_table(table_name, properties)

	if success:
		print("[TablesEditor] Saved table: %s" % table_name)
		current_table_name = table_name
		_refresh_table_list()
		table_saved.emit(table_name)
	else:
		_show_error("Failed to save table")


func _on_delete_table_pressed() -> void:
	if current_table_name.is_empty():
		return

	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Delete table '%s'?\nThis cannot be undone." % current_table_name
	confirm.confirmed.connect(func():
		var success = database_system.remove_table(current_table_name)
		if success:
			print("[TablesEditor] Deleted table: %s" % current_table_name)
			_clear_editor()
			_refresh_table_list()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())

	add_child(confirm)
	confirm.popup_centered()


func _on_table_name_changed(new_text: String) -> void:
	save_table_btn.disabled = new_text.strip_edges().is_empty()


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
