@tool
extends HBoxContainer

## Editor row for a single table field definition.
## Layout: Name | FieldName | Type | LineEditAutocomplete | Default | [editor] | X

signal remove_requested()
signal validation_changed(error: String)

var default_value_edit: Control
var _current_editor_type: ResourceGenerator.DefaultEditorType = \
		ResourceGenerator.DefaultEditorType.NONE

## Deferred initial data (set before _ready via set_field)
var _deferred_name: String = ""
var _deferred_type_string: String = "String"
var _deferred_default: Variant = null
var _deferred_constraints: Dictionary = {}
var _has_deferred_data: bool = false

## Saved type string before FK override (restored when FK is cleared)
var _pre_fk_type: String = ""
var _deferred_table_names: Array[String] = []
var _deferred_exclude_table: String = ""


func _ready() -> void:
	var provider := TypeSuggestionProvider.new()
	%TypeAutocomplete.provider = provider
	%TypeAutocomplete.text_committed.connect(_on_type_committed)
	%TypeAutocomplete.validation_changed.connect(func(_has_err: bool):
		validation_changed.emit(%TypeAutocomplete.last_error)
	)
	%RemoveBtn.pressed.connect(func(): remove_requested.emit())
	%ForeignKeySelect.item_selected.connect(_on_fk_selected)

	# Apply deferred table names before field data (FK needs the dropdown populated)
	if not _deferred_table_names.is_empty():
		set_table_names(_deferred_table_names, _deferred_exclude_table)
		_deferred_table_names = []
		_deferred_exclude_table = ""

	if _has_deferred_data:
		_apply_field(_deferred_name, _deferred_type_string, _deferred_default,
				_deferred_constraints)
		_has_deferred_data = false
	else:
		_apply_type("String")


func set_field(field_name: String, type_string: String, default_value: Variant,
		constraints: Dictionary = {}) -> void:
	if not is_node_ready():
		_deferred_name = field_name
		_deferred_type_string = type_string
		_deferred_default = default_value
		_deferred_constraints = constraints
		_has_deferred_data = true
		return
	_apply_field(field_name, type_string, default_value, constraints)


func _apply_field(field_name: String, type_string: String, default_value: Variant,
		constraints: Dictionary = {}) -> void:
	%FieldNameEdit.text = field_name
	%TypeAutocomplete.set_text(type_string)
	_apply_type(type_string)
	_set_default_value(default_value)
	_apply_constraints(constraints)


func _apply_constraints(constraints: Dictionary) -> void:
	%RequiredCheckBox.button_pressed = constraints.get("required", false)
	if constraints.has("foreign_key"):
		var fk_table: String = constraints["foreign_key"]
		# Find and select the FK table in the dropdown
		for i in range(%ForeignKeySelect.item_count):
			if %ForeignKeySelect.get_item_text(i) == fk_table:
				%ForeignKeySelect.selected = i
				_apply_fk(fk_table)
				return
	# No FK — select first item ("— No FK —")
	if %ForeignKeySelect.item_count > 0:
		%ForeignKeySelect.selected = 0


## Populate the ForeignKey dropdown with available table names.
## exclude_table: name of the current table (can't FK to itself).
func set_table_names(names: Array[String], exclude_table: String = "") -> void:
	if not is_node_ready():
		_deferred_table_names = names
		_deferred_exclude_table = exclude_table
		return
	%ForeignKeySelect.clear()
	%ForeignKeySelect.add_item("— No FK —")
	for table_name in names:
		if table_name != exclude_table:
			%ForeignKeySelect.add_item(table_name)


func _on_fk_selected(index: int) -> void:
	if index <= 0:
		# "— No FK —" selected — restore previous type
		%TypeAutocomplete.set_text(_pre_fk_type if not _pre_fk_type.is_empty() else "String")
		%TypeAutocomplete.set_editable(true)
		_apply_type(%TypeAutocomplete.get_text())
	else:
		var fk_table: String = %ForeignKeySelect.get_item_text(index)
		_apply_fk(fk_table)


func _apply_fk(fk_table: String) -> void:
	# Save current type before overriding
	var current_type: String = %TypeAutocomplete.get_text()
	# Don't save the FK type itself as the pre-FK type
	if current_type != fk_table and not current_type.ends_with("Ids.Id"):
		_pre_fk_type = current_type
	# FK generates a Resource reference (class name directly, not enum)
	%TypeAutocomplete.set_text(fk_table)
	%TypeAutocomplete.set_editable(false)
	_apply_type(%TypeAutocomplete.get_text())


func _on_type_committed(ts: String) -> void:
	_apply_type(ts)


func _apply_type(ts: String) -> void:
	_current_editor_type = ResourceGenerator.get_editor_type(ts)
	_update_default_value_editor()


func _update_default_value_editor() -> void:
	for child in %DefaultValueContainer.get_children():
		child.queue_free()

	var editor: Control
	match _current_editor_type:
		ResourceGenerator.DefaultEditorType.INT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 1
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.DefaultEditorType.FLOAT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 0.01
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.DefaultEditorType.STRING:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "default value"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.DefaultEditorType.BOOL:
			var check_box = CheckBox.new()
			editor = check_box

		ResourceGenerator.DefaultEditorType.TEXTURE2D:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "res://path/to/texture.png"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.DefaultEditorType.VECTOR2:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.DefaultEditorType.VECTOR3:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.DefaultEditorType.COLOR:
			var color_picker = ColorPickerButton.new()
			color_picker.custom_minimum_size = Vector2(80, 0)
			editor = color_picker

		_:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "{} or []"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

	%DefaultValueContainer.add_child(editor)
	default_value_edit = editor


func has_validation_error() -> bool:
	return %TypeAutocomplete.has_error


func get_validation_error() -> String:
	return %TypeAutocomplete.last_error


func get_field_data() -> Dictionary:
	var name_text: String = %FieldNameEdit.text.strip_edges()
	if name_text.is_empty():
		return {}
	var type_string: String = %TypeAutocomplete.get_text()
	if type_string.is_empty():
		return {}
	var result := {
		"name": name_text,
		"type_string": type_string,
		"default": _get_default_value()
	}
	var constraints := {}
	if %RequiredCheckBox.button_pressed:
		constraints["required"] = true
	var fk_idx: int = %ForeignKeySelect.selected
	if fk_idx > 0:
		constraints["foreign_key"] = %ForeignKeySelect.get_item_text(fk_idx)
	if not constraints.is_empty():
		result["constraints"] = constraints
	return result


func _set_default_value(value: Variant) -> void:
	if not default_value_edit:
		return

	match _current_editor_type:
		ResourceGenerator.DefaultEditorType.INT, ResourceGenerator.DefaultEditorType.FLOAT:
			if default_value_edit is SpinBox:
				default_value_edit.value = value if value != null else 0

		ResourceGenerator.DefaultEditorType.STRING:
			if default_value_edit is LineEdit:
				default_value_edit.text = value if value != null else ""

		ResourceGenerator.DefaultEditorType.BOOL:
			if default_value_edit is CheckBox:
				default_value_edit.button_pressed = value if value != null else false

		ResourceGenerator.DefaultEditorType.TEXTURE2D:
			if default_value_edit is LineEdit:
				if value is Texture2D:
					default_value_edit.text = value.resource_path
				elif value is String:
					default_value_edit.text = value

		ResourceGenerator.DefaultEditorType.VECTOR2:
			if default_value_edit is LineEdit and value is Vector2:
				default_value_edit.text = "%f, %f" % [value.x, value.y]

		ResourceGenerator.DefaultEditorType.VECTOR3:
			if default_value_edit is LineEdit and value is Vector3:
				default_value_edit.text = "%f, %f, %f" % [value.x, value.y, value.z]

		ResourceGenerator.DefaultEditorType.COLOR:
			if default_value_edit is ColorPickerButton:
				default_value_edit.color = value if value is Color else Color.WHITE


func _get_default_value() -> Variant:
	if not default_value_edit:
		return null

	match _current_editor_type:
		ResourceGenerator.DefaultEditorType.INT:
			if default_value_edit is SpinBox:
				return int(default_value_edit.value)

		ResourceGenerator.DefaultEditorType.FLOAT:
			if default_value_edit is SpinBox:
				return default_value_edit.value

		ResourceGenerator.DefaultEditorType.STRING:
			if default_value_edit is LineEdit:
				return default_value_edit.text

		ResourceGenerator.DefaultEditorType.BOOL:
			if default_value_edit is CheckBox:
				return default_value_edit.button_pressed

		ResourceGenerator.DefaultEditorType.TEXTURE2D:
			if default_value_edit is LineEdit:
				var path = default_value_edit.text.strip_edges()
				if path.is_empty():
					return null
				return path

		ResourceGenerator.DefaultEditorType.VECTOR2:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
				return Vector2.ZERO

		ResourceGenerator.DefaultEditorType.VECTOR3:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 3:
					return Vector3(
						float(parts[0].strip_edges()),
						float(parts[1].strip_edges()),
						float(parts[2].strip_edges()))
				return Vector3.ZERO

		ResourceGenerator.DefaultEditorType.COLOR:
			if default_value_edit is ColorPickerButton:
				return default_value_edit.color

	return null
