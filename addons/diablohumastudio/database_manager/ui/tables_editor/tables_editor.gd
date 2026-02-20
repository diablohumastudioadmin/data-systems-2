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
@onready var fields_container: VBoxContainer = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/FieldsScroll/FieldsContainer
@onready var add_field_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/AddFieldBtn
@onready var save_table_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/SaveTableBtn
@onready var delete_table_btn: Button = $VBox/HBox/EditorPanel/MarginContainer/EditorVBox/ButtonBox/DeleteTableBtn

@onready var new_table_btn: Button = $VBox/VBoxContainer/TableListPanel/VBox/HBoxContainer/NewTableBtn
@onready var refresh_btn: Button = $VBox/VBoxContainer/TableListPanel/VBox/HBoxContainer/RefreshBtn

var database_manager: DatabaseManager: set = _set_database_manager
var current_table_name: String = ""
var field_rows: Array = []  # Array of FieldEditorRow nodes
var _initialized: bool = false


func _set_database_manager(value: DatabaseManager) -> void:
	database_manager = value
	if value and is_node_ready() and not _initialized:
		_initialize()


func _ready() -> void:
	if not database_manager:
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
	add_field_btn.pressed.connect(_on_add_field_pressed)
	save_table_btn.pressed.connect(_on_save_table_pressed)
	delete_table_btn.pressed.connect(_on_delete_table_pressed)
	table_name_edit.text_changed.connect(_on_table_name_changed)


func _refresh_table_list() -> void:
	table_list.clear()
	var table_names = database_manager.get_table_names()
	for table_name in table_names:
		table_list.add_item(table_name)


func _on_table_list_item_selected(index: int) -> void:
	var table_name = table_list.get_item_text(index)
	_load_table(table_name)


func _load_table(table_name: String) -> void:
	current_table_name = table_name
	table_name_edit.text = table_name
	table_name_edit.editable = true
	_clear_fields()

	var fields = database_manager.get_table_fields(table_name)
	for field in fields:
		var ts = ResourceGenerator.property_info_to_type_string(field)
		_add_field_row(field.name, ts, field.default)

	table_selected.emit(table_name)


func _clear_editor() -> void:
	current_table_name = ""
	table_name_edit.text = ""
	table_name_edit.editable = true
	_clear_fields()


func _clear_fields() -> void:
	for row in field_rows:
		row.queue_free()
	field_rows.clear()


func _on_new_table_pressed() -> void:
	_clear_editor()
	table_list.deselect_all()


func _add_field_row(
		field_name: String = "",
		type_string: String = "String",
		default_value: Variant = null) -> void:
	var row = preload("field_editor_row.tscn").instantiate()
	row.set_field(field_name, type_string, default_value)
	row.remove_requested.connect(_on_field_remove_requested.bind(row))

	fields_container.add_child(row)
	field_rows.append(row)


func _on_add_field_pressed() -> void:
	_add_field_row()


func _on_field_remove_requested(row: Node) -> void:
	field_rows.erase(row)
	row.queue_free()


func _on_save_table_pressed() -> void:
	var table_name = table_name_edit.text.strip_edges()

	if table_name.is_empty():
		_show_error("Table name cannot be empty")
		return

	# Collect fields from UI rows
	var fields: Array[Dictionary] = []
	for row in field_rows:
		var field_data = row.get_field_data()
		if field_data.is_empty():
			continue
		fields.append(field_data)

	var success = false
	if current_table_name.is_empty():
		success = database_manager.add_table(table_name, fields)
	elif table_name != current_table_name:
		success = database_manager.rename_table(current_table_name, table_name, fields)
	else:
		success = database_manager.update_table(table_name, fields)

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
		var success = database_manager.remove_table(current_table_name)
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
