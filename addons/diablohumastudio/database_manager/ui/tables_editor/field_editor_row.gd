@tool
extends HBoxContainer

## Reusable field editor row for TablesEditor.
## Layout: Name | FieldName | Type | FieldType | [InnerType] | Default | [editor] | X

signal remove_requested()

@onready var field_name_edit: LineEdit = %FieldNameEdit
@onready var field_type_option: OptionButton = %FieldTypeOption
@onready var inner_type_container: HBoxContainer = %InnerTypeContainer
@onready var inner_type_label: Label = %InnerTypeLabel
@onready var inner_type_option: OptionButton = %InnerTypeOption
@onready var dict_sep_label: Label = %DictSepLabel
@onready var dict_value_option: OptionButton = %DictValueOption
@onready var default_value_container: HBoxContainer = %DefaultValueContainer
@onready var remove_btn: Button = %RemoveBtn

var default_value_edit: Control
var current_type: ResourceGenerator.FieldType = ResourceGenerator.FieldType.STRING
var current_inner_type: int = ResourceGenerator.FieldType.INT  # element for Array, key for Dict
var current_value_type: int = ResourceGenerator.FieldType.INT  # value type for Typed Dictionary

## Deferred initial data (set before _ready via set_field)
var _deferred_name: String = ""
var _deferred_type: ResourceGenerator.FieldType = ResourceGenerator.FieldType.STRING
var _deferred_inner_type: int = -1
var _deferred_value_type: int = -1
var _deferred_default: Variant = null
var _has_deferred_data: bool = false


func _ready() -> void:
	_populate_type_options()
	_populate_inner_type_options()
	field_type_option.item_selected.connect(_on_type_changed)
	inner_type_option.item_selected.connect(_on_inner_type_changed)
	dict_value_option.item_selected.connect(_on_dict_value_type_changed)
	remove_btn.pressed.connect(func(): remove_requested.emit())

	if _has_deferred_data:
		_apply_deferred_data()
	else:
		_update_default_value_editor()


func _populate_type_options() -> void:
	field_type_option.clear()
	field_type_option.add_item("int", ResourceGenerator.FieldType.INT)
	field_type_option.add_item("float", ResourceGenerator.FieldType.FLOAT)
	field_type_option.add_item("String", ResourceGenerator.FieldType.STRING)
	field_type_option.add_item("bool", ResourceGenerator.FieldType.BOOL)
	field_type_option.add_item("Texture2D", ResourceGenerator.FieldType.TEXTURE2D)
	field_type_option.add_item("Vector2", ResourceGenerator.FieldType.VECTOR2)
	field_type_option.add_item("Vector3", ResourceGenerator.FieldType.VECTOR3)
	field_type_option.add_item("Color", ResourceGenerator.FieldType.COLOR)
	field_type_option.add_item("Array", ResourceGenerator.FieldType.ARRAY)
	field_type_option.add_item("Typed Array", ResourceGenerator.FieldType.TYPED_ARRAY)
	field_type_option.add_item("Dictionary", ResourceGenerator.FieldType.DICTIONARY)
	field_type_option.add_item("Typed Dictionary", ResourceGenerator.FieldType.TYPED_DICTIONARY)


func _populate_inner_type_options() -> void:
	for btn in [inner_type_option, dict_value_option]:
		btn.clear()
		btn.add_item("int", ResourceGenerator.FieldType.INT)
		btn.add_item("float", ResourceGenerator.FieldType.FLOAT)
		btn.add_item("String", ResourceGenerator.FieldType.STRING)
		btn.add_item("bool", ResourceGenerator.FieldType.BOOL)
		btn.add_item("Vector2", ResourceGenerator.FieldType.VECTOR2)
		btn.add_item("Vector3", ResourceGenerator.FieldType.VECTOR3)
		btn.add_item("Color", ResourceGenerator.FieldType.COLOR)


func _update_inner_type_visibility() -> void:
	match current_type:
		ResourceGenerator.FieldType.TYPED_ARRAY:
			inner_type_label.text = "of"
			inner_type_label.visible = true
			inner_type_option.visible = true
			dict_sep_label.visible = false
			dict_value_option.visible = false
		ResourceGenerator.FieldType.TYPED_DICTIONARY:
			inner_type_label.text = "k"
			inner_type_label.visible = true
			inner_type_option.visible = true
			dict_sep_label.visible = true
			dict_value_option.visible = true
		_:
			inner_type_label.visible = false
			inner_type_option.visible = false
			dict_sep_label.visible = false
			dict_value_option.visible = false


func _update_default_value_editor() -> void:
	for child in default_value_container.get_children():
		child.queue_free()

	var editor: Control
	match current_type:
		ResourceGenerator.FieldType.INT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 1
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.FieldType.FLOAT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 0.01
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.FieldType.STRING:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "default value"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.FieldType.BOOL:
			var check_box = CheckBox.new()
			editor = check_box

		ResourceGenerator.FieldType.TEXTURE2D:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "res://path/to/texture.png"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.FieldType.VECTOR2:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.FieldType.VECTOR3:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.FieldType.COLOR:
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


func _on_type_changed(index: int) -> void:
	current_type = field_type_option.get_item_id(index) as ResourceGenerator.FieldType
	_update_inner_type_visibility()
	_update_default_value_editor()


func _on_inner_type_changed(index: int) -> void:
	current_inner_type = inner_type_option.get_item_id(index)


func _on_dict_value_type_changed(index: int) -> void:
	current_value_type = dict_value_option.get_item_id(index)


func set_field(
		field_name: String,
		field_type: ResourceGenerator.FieldType,
		default_value: Variant,
		inner_type: int = -1,
		value_type: int = -1) -> void:
	if not is_node_ready():
		_deferred_name = field_name
		_deferred_type = field_type
		_deferred_inner_type = inner_type
		_deferred_value_type = value_type
		_deferred_default = default_value
		_has_deferred_data = true
		return
	_apply_field(field_name, field_type, default_value, inner_type, value_type)


func _apply_deferred_data() -> void:
	_apply_field(
		_deferred_name, _deferred_type, _deferred_default,
		_deferred_inner_type, _deferred_value_type)
	_has_deferred_data = false


func _apply_field(
		field_name: String,
		field_type: ResourceGenerator.FieldType,
		default_value: Variant,
		inner_type: int = -1,
		value_type: int = -1) -> void:
	field_name_edit.text = field_name
	current_type = field_type

	for i in range(field_type_option.item_count):
		if field_type_option.get_item_id(i) == field_type:
			field_type_option.selected = i
			break

	_update_inner_type_visibility()

	if inner_type >= 0:
		current_inner_type = inner_type
		_select_option(inner_type_option, inner_type)

	if value_type >= 0:
		current_value_type = value_type
		_select_option(dict_value_option, value_type)

	_update_default_value_editor()
	_set_default_value(default_value)


func _select_option(btn: OptionButton, id: int) -> void:
	for i in range(btn.item_count):
		if btn.get_item_id(i) == id:
			btn.selected = i
			return


func _set_default_value(value: Variant) -> void:
	if not default_value_edit:
		return

	match current_type:
		ResourceGenerator.FieldType.INT, ResourceGenerator.FieldType.FLOAT:
			if default_value_edit is SpinBox:
				default_value_edit.value = value if value != null else 0

		ResourceGenerator.FieldType.STRING:
			if default_value_edit is LineEdit:
				default_value_edit.text = value if value != null else ""

		ResourceGenerator.FieldType.BOOL:
			if default_value_edit is CheckBox:
				default_value_edit.button_pressed = value if value != null else false

		ResourceGenerator.FieldType.TEXTURE2D:
			if default_value_edit is LineEdit:
				if value is Texture2D:
					default_value_edit.text = value.resource_path
				elif value is String:
					default_value_edit.text = value

		ResourceGenerator.FieldType.VECTOR2:
			if default_value_edit is LineEdit and value is Vector2:
				default_value_edit.text = "%f, %f" % [value.x, value.y]

		ResourceGenerator.FieldType.VECTOR3:
			if default_value_edit is LineEdit and value is Vector3:
				default_value_edit.text = "%f, %f, %f" % [value.x, value.y, value.z]

		ResourceGenerator.FieldType.COLOR:
			if default_value_edit is ColorPickerButton:
				default_value_edit.color = value if value is Color else Color.WHITE


func get_field_data() -> Dictionary:
	var name_text = field_name_edit.text.strip_edges()
	if name_text.is_empty():
		return {}

	var data := {
		"name": name_text,
		"type": current_type,
		"default": _get_default_value()
	}

	match current_type:
		ResourceGenerator.FieldType.TYPED_ARRAY:
			data["element_type"] = current_inner_type
		ResourceGenerator.FieldType.TYPED_DICTIONARY:
			data["key_type"] = current_inner_type
			data["value_type"] = current_value_type

	return data


func _get_default_value() -> Variant:
	if not default_value_edit:
		return null

	match current_type:
		ResourceGenerator.FieldType.INT, ResourceGenerator.FieldType.FLOAT:
			if default_value_edit is SpinBox:
				return default_value_edit.value

		ResourceGenerator.FieldType.STRING:
			if default_value_edit is LineEdit:
				return default_value_edit.text

		ResourceGenerator.FieldType.BOOL:
			if default_value_edit is CheckBox:
				return default_value_edit.button_pressed

		ResourceGenerator.FieldType.TEXTURE2D:
			if default_value_edit is LineEdit:
				var path = default_value_edit.text.strip_edges()
				if path.is_empty():
					return null
				return path

		ResourceGenerator.FieldType.VECTOR2:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
				return Vector2.ZERO

		ResourceGenerator.FieldType.VECTOR3:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 3:
					return Vector3(
						float(parts[0].strip_edges()),
						float(parts[1].strip_edges()),
						float(parts[2].strip_edges()))
				return Vector3.ZERO

		ResourceGenerator.FieldType.COLOR:
			if default_value_edit is ColorPickerButton:
				return default_value_edit.color

		ResourceGenerator.FieldType.ARRAY, ResourceGenerator.FieldType.TYPED_ARRAY:
			return []

		ResourceGenerator.FieldType.DICTIONARY, ResourceGenerator.FieldType.TYPED_DICTIONARY:
			return {}

	return null
