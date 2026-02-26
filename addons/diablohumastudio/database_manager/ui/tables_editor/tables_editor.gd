@tool
extends Control

## Visual editor for creating and editing table schemas

signal table_selected(table_name: String)
signal table_saved(table_name: String)

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
	%TableList.item_selected.connect(_on_table_list_item_selected)
	%NewTableBtn.pressed.connect(_on_new_table_pressed)
	%RefreshBtn.pressed.connect(_refresh_table_list)
	%AddFieldBtn.pressed.connect(_on_add_field_pressed)
	%SaveTableBtn.pressed.connect(_on_save_table_pressed)
	%DeleteTableBtn.pressed.connect(_on_delete_table_pressed)
	%TableNameEdit.text_changed.connect(_on_table_name_changed)
	%ParentTableSelect.item_selected.connect(_on_parent_selected)


# --- Table List (with hierarchy) ---------------------------------------------

func _refresh_table_list() -> void:
	%TableList.clear()
	var sorted_names: Array[String] = _get_sorted_table_names()
	for table_name in sorted_names:
		var depth: int = _get_depth(table_name)
		var display: String = table_name
		if depth > 0:
			display = "%s%s" % ["  ".repeat(depth), table_name]
		%TableList.add_item(display)

	# Auto-select first table if none selected
	if %TableList.item_count > 0 and current_table_name.is_empty():
		%TableList.select(0)
		_on_table_list_item_selected(0)


func _get_sorted_table_names() -> Array[String]:
	var all_names: Array[String] = []
	all_names.assign(database_manager.get_table_names())
	var sorted: Array[String] = []
	for table_name in all_names:
		if database_manager.get_parent_table(table_name).is_empty():
			_add_with_children(table_name, sorted)
	# Add any orphans (shouldn't happen, but safety)
	for table_name in all_names:
		if table_name not in sorted:
			sorted.append(table_name)
	return sorted


func _add_with_children(table_name: String, sorted: Array[String]) -> void:
	sorted.append(table_name)
	for child in database_manager.get_child_tables(table_name):
		_add_with_children(child, sorted)


func _get_depth(table_name: String) -> int:
	var depth := 0
	var current: String = database_manager.get_parent_table(table_name)
	while not current.is_empty():
		depth += 1
		current = database_manager.get_parent_table(current)
	return depth


func _on_table_list_item_selected(index: int) -> void:
	var display_text: String = %TableList.get_item_text(index)
	var table_name: String = display_text.strip_edges()
	_load_table(table_name)


# --- Parent Selection --------------------------------------------------------

func _refresh_parent_select(exclude_table: String = "") -> void:
	%ParentTableSelect.clear()
	%ParentTableSelect.add_item("— No Parent —")
	for table_name in database_manager.get_table_names():
		if table_name == exclude_table:
			continue
		# Exclude descendants of exclude_table (would create cycle)
		if not exclude_table.is_empty() and database_manager.is_descendant_of(table_name, exclude_table):
			continue
		%ParentTableSelect.add_item(table_name)


func _select_parent_in_dropdown(parent_name: String) -> void:
	if parent_name.is_empty():
		%ParentTableSelect.selected = 0
		return
	for i in range(%ParentTableSelect.item_count):
		if %ParentTableSelect.get_item_text(i) == parent_name:
			%ParentTableSelect.selected = i
			return
	%ParentTableSelect.selected = 0


func _get_selected_parent() -> String:
	if %ParentTableSelect.selected <= 0:
		return ""
	return %ParentTableSelect.get_item_text(%ParentTableSelect.selected)


func _on_parent_selected(_index: int) -> void:
	_rebuild_inherited_fields_display()


# --- Inherited Fields Cascade Display ----------------------------------------

func _rebuild_inherited_fields_display() -> void:
	for child in %InheritedFieldsContainer.get_children():
		child.queue_free()

	var parent_name: String = _get_selected_parent()
	if parent_name.is_empty():
		%InheritedFieldsContainer.visible = false
		%OwnFieldsLabel.visible = false
		return

	%InheritedFieldsContainer.visible = true
	%OwnFieldsLabel.visible = true

	var chain: Array[Dictionary] = database_manager.get_inheritance_chain(parent_name)
	for entry in chain:
		var header := Label.new()
		header.text = "— %s —" % entry.table_name
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.22352941, 0.22352941, 0.22352941, 1)
		header.add_theme_stylebox_override("normal", style)
		%InheritedFieldsContainer.add_child(header)

		for field in entry.fields:
			var row := _create_readonly_field_row(field)
			%InheritedFieldsContainer.add_child(row)


func _create_readonly_field_row(field: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = field.name
	name_label.custom_minimum_size.x = 150
	name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox.add_child(name_label)

	var type_label := Label.new()
	var type_str: String = ""
	if field.has("type_string"):
		type_str = field.type_string
	elif field.has("type"):
		type_str = ResourceGenerator.property_info_to_type_string(field)
	type_label.text = ": %s" % type_str
	type_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox.add_child(type_label)

	return hbox


# --- Table Loading -----------------------------------------------------------

func _load_table(table_name: String) -> void:
	current_table_name = table_name
	%TableNameEdit.text = table_name
	%TableNameEdit.editable = true
	_clear_fields()

	# Parent selection
	var parent_name: String = database_manager.get_parent_table(table_name)
	_refresh_parent_select(table_name)
	_select_parent_in_dropdown(parent_name)
	_rebuild_inherited_fields_display()

	# Load only own fields (not inherited)
	var field_constraints: Dictionary = database_manager.get_field_constraints(table_name)
	var fields: Array[Dictionary] = database_manager.get_own_table_fields(table_name)
	for field in fields:
		var ts: String = ResourceGenerator.property_info_to_type_string(field)
		var fc: Dictionary = field_constraints.get(field.name, {})
		_add_field_row(field.name, ts, field.default, fc)

	table_selected.emit(table_name)


func _clear_editor() -> void:
	current_table_name = ""
	%TableNameEdit.text = ""
	%TableNameEdit.editable = true
	_clear_fields()
	_refresh_parent_select()
	_select_parent_in_dropdown("")
	_rebuild_inherited_fields_display()


func _clear_fields() -> void:
	for row in field_rows:
		row.queue_free()
	field_rows.clear()
	if %ValidationErrorLabel:
		%ValidationErrorLabel.text = ""


func _on_new_table_pressed() -> void:
	_clear_editor()
	%TableList.deselect_all()


func _add_field_row(
		field_name: String = "",
		type_string: String = "String",
		default_value: Variant = null,
		constraints: Dictionary = {}) -> void:
	var row = preload("table_field_editor/table_field_editor.tscn").instantiate()
	row.set_table_names(database_manager.get_table_names(), current_table_name)
	row.set_field(field_name, type_string, default_value, constraints)
	row.remove_requested.connect(_on_field_remove_requested.bind(row))
	row.validation_changed.connect(_on_field_validation_changed)

	%FieldsContainer.add_child(row)
	field_rows.append(row)


func _on_add_field_pressed() -> void:
	_add_field_row()


func _on_field_remove_requested(row: Node) -> void:
	field_rows.erase(row)
	row.queue_free()
	_update_save_button()
	_refresh_error_label()


func _on_field_validation_changed(_error: String) -> void:
	_update_save_button()
	_refresh_error_label()


# --- Save / Delete -----------------------------------------------------------

func _on_save_table_pressed() -> void:
	var table_name = %TableNameEdit.text.strip_edges()

	if table_name.is_empty():
		_show_error("Table name cannot be empty")
		return

	if not table_name.is_valid_identifier():
		_show_error("Table name must be a valid identifier")
		return

	for row in field_rows:
		if row.has_validation_error():
			_show_error("Fix type errors before saving")
			return

	# Collect fields and constraints from UI rows
	var fields: Array[Dictionary] = []
	var constraints: Dictionary = {}
	var existing_names: Array[String] = []

	for row in field_rows:
		var field_data = row.get_field_data()
		if field_data.is_empty():
			continue

		var validation_err := FieldValidator.validate_field_name(field_data.name, existing_names)
		if not validation_err.is_empty():
			_show_error(validation_err)
			return
		existing_names.append(field_data.name)

		if field_data.has("constraints"):
			constraints[field_data.name] = field_data.constraints
		fields.append(field_data)

	var parent_name: String = _get_selected_parent()

	# Check for destructive changes
	if not current_table_name.is_empty() and table_name == current_table_name:
		var old_fields = database_manager.get_own_table_fields(current_table_name)
		var destructive_warning := ""
		for old_f in old_fields:
			var found = false
			var type_changed = false
			for new_f in fields:
				if new_f.name == old_f.name:
					found = true
					var old_type_str = ResourceGenerator.property_info_to_type_string(old_f)
					var new_type_str = new_f.type_string if new_f.has("type_string") else ResourceGenerator.property_info_to_type_string(new_f)
					if old_type_str != new_type_str:
						type_changed = true
					break
			if not found:
				destructive_warning += "• Field '%s' was removed.\n" % old_f.name
			elif type_changed:
				destructive_warning += "• Field '%s' type changed.\n" % old_f.name

		if not destructive_warning.is_empty():
			var confirm = ConfirmationDialog.new()
			confirm.dialog_text = "Destructive schema changes detected:\n\n%s\nThis may cause data loss in existing instances. Continue?" % destructive_warning
			confirm.confirmed.connect(func():
				_execute_save(table_name, fields, constraints, parent_name)
				confirm.queue_free()
			)
			confirm.canceled.connect(func(): confirm.queue_free())
			add_child(confirm)
			confirm.popup_centered()
			return

	_execute_save(table_name, fields, constraints, parent_name)


func _execute_save(table_name: String, fields: Array[Dictionary], constraints: Dictionary, parent_name: String) -> void:
	var success = false
	if current_table_name.is_empty():
		success = database_manager.add_table(table_name, fields, constraints, parent_name)
	elif table_name != current_table_name:
		success = database_manager.rename_table(current_table_name, table_name, fields, constraints, parent_name)
	else:
		success = database_manager.update_table(table_name, fields, constraints, parent_name)

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

	# Block deletion of parent tables
	var children: Array[String] = database_manager.get_child_tables(current_table_name)
	if not children.is_empty():
		_show_error("Cannot delete '%s': it has child tables: %s\nDelete or re-parent children first." % [
			current_table_name, ", ".join(children)])
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


func _on_table_name_changed(_new_text: String) -> void:
	_update_save_button()


func _refresh_error_label() -> void:
	for row in field_rows:
		if row.has_validation_error():
			%ValidationErrorLabel.text = row.get_validation_error()
			return
	%ValidationErrorLabel.text = ""


func _update_save_button() -> void:
	var any_error := false
	for row in field_rows:
		if row.has_validation_error():
			any_error = true
			break
	%SaveTableBtn.disabled = any_error \
			or %TableNameEdit.text.strip_edges().is_empty()


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
