@tool
extends HBoxContainer

## Reusable field editor row for TablesEditor.
## Layout: Name | FieldName | Type | TypeEdit | Default | [editor] | X

signal remove_requested()

@onready var field_name_edit: LineEdit = %FieldNameEdit
@onready var type_edit: LineEdit = %TypeEdit
@onready var default_value_container: HBoxContainer = %DefaultValueContainer
@onready var remove_btn: Button = %RemoveBtn

var default_value_edit: Control
var _current_editor_type: ResourceGenerator.DefaultEditorType = ResourceGenerator.DefaultEditorType.NONE

## Deferred initial data (set before _ready via set_field)
var _deferred_name: String = ""
var _deferred_type_string: String = "String"
var _deferred_default: Variant = null
var _has_deferred_data: bool = false


func _ready() -> void:
	type_edit.focus_exited.connect(_on_type_edit_focus_exited)
	type_edit.text_submitted.connect(func(_t): _on_type_edit_focus_exited())
	remove_btn.pressed.connect(func(): remove_requested.emit())

	if _has_deferred_data:
		_apply_field(_deferred_name, _deferred_type_string, _deferred_default)
		_has_deferred_data = false
	else:
		_apply_type("String")


func set_field(field_name: String, type_string: String, default_value: Variant) -> void:
	if not is_node_ready():
		_deferred_name = field_name
		_deferred_type_string = type_string
		_deferred_default = default_value
		_has_deferred_data = true
		return
	_apply_field(field_name, type_string, default_value)


func _apply_field(field_name: String, type_string: String, default_value: Variant) -> void:
	field_name_edit.text = field_name
	type_edit.text = type_string
	_apply_type(type_string)
	_set_default_value(default_value)


func _on_type_edit_focus_exited() -> void:
	var ts := type_edit.text.strip_edges()
	var valid := ts.is_empty() or ResourceGenerator.is_valid_type_string(ts)
	if valid:
		type_edit.remove_theme_color_override("font_color")
	else:
		type_edit.add_theme_color_override("font_color", Color.RED)
	_apply_type(ts)


func _apply_type(ts: String) -> void:
	_current_editor_type = ResourceGenerator.get_editor_type(ts)
	_update_default_value_editor()


func _update_default_value_editor() -> void:
	for child in default_value_container.get_children():
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

	default_value_container.add_child(editor)
	default_value_edit = editor


func get_field_data() -> Dictionary:
	var name_text := field_name_edit.text.strip_edges()
	if name_text.is_empty():
		return {}
	var type_string := type_edit.text.strip_edges()
	if type_string.is_empty():
		return {}
	return {
		"name": name_text,
		"type_string": type_string,
		"default": _get_default_value()
	}


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
