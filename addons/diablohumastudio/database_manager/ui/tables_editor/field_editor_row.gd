@tool
extends HBoxContainer

## Reusable field editor row for TablesEditor (scene-based).
## Shows: Name | FieldName | Type | FieldType | [of ElementType] | Default: | [editor] | X

signal remove_requested()

@onready var field_name_edit: LineEdit = %FieldNameEdit
@onready var field_type_option: OptionButton = %FieldTypeOption
@onready var default_value_container: HBoxContainer = %DefaultValueContainer
@onready var remove_btn: Button = %RemoveBtn

var default_value_edit: Control  # Current editor inside DefaultValueContainer
var current_type: ResourceGenerator.FieldType = ResourceGenerator.FieldType.STRING
var current_element_type: int = ResourceGenerator.FieldType.INT  # -1 = untyped

var element_type_container: HBoxContainer
var element_type_option: OptionButton

## Deferred initial data (set before _ready via set_field)
var _deferred_name: String = ""
var _deferred_type: ResourceGenerator.FieldType = ResourceGenerator.FieldType.STRING
var _deferred_element_type: int = -1
var _deferred_default: Variant = null
var _has_deferred_data: bool = false


func _ready() -> void:
	_populate_type_options()
	_build_element_type_selector()
	field_type_option.item_selected.connect(_on_type_changed)
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
	field_type_option.add_item("Dictionary", ResourceGenerator.FieldType.DICTIONARY)


func _build_element_type_selector() -> void:
	element_type_container = HBoxContainer.new()
	element_type_container.visible = false

	var label = Label.new()
	label.text = "of"
	element_type_container.add_child(label)

	element_type_option = OptionButton.new()
	element_type_option.add_item("int", ResourceGenerator.FieldType.INT)
	element_type_option.add_item("float", ResourceGenerator.FieldType.FLOAT)
	element_type_option.add_item("String", ResourceGenerator.FieldType.STRING)
	element_type_option.add_item("bool", ResourceGenerator.FieldType.BOOL)
	element_type_option.add_item("Vector2", ResourceGenerator.FieldType.VECTOR2)
	element_type_option.add_item("Vector3", ResourceGenerator.FieldType.VECTOR3)
	element_type_option.add_item("Color", ResourceGenerator.FieldType.COLOR)
	element_type_option.item_selected.connect(_on_element_type_changed)
	element_type_container.add_child(element_type_option)

	# Insert right after the type dropdown
	add_child(element_type_container)
	move_child(element_type_container, field_type_option.get_index() + 1)


func _update_default_value_editor() -> void:
	# Clear previous editor
	for child in default_value_container.get_children():
		child.queue_free()

	# Create new editor based on current type
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
	element_type_container.visible = (current_type == ResourceGenerator.FieldType.ARRAY)
	_update_default_value_editor()


func _on_element_type_changed(index: int) -> void:
	current_element_type = element_type_option.get_item_id(index)


func set_field(field_name: String, field_type: ResourceGenerator.FieldType, default_value: Variant, element_type: int = -1) -> void:
	if not is_node_ready():
		_deferred_name = field_name
		_deferred_type = field_type
		_deferred_element_type = element_type
		_deferred_default = default_value
		_has_deferred_data = true
		return

	_apply_field(field_name, field_type, default_value, element_type)


func _apply_deferred_data() -> void:
	_apply_field(_deferred_name, _deferred_type, _deferred_default, _deferred_element_type)
	_has_deferred_data = false


func _apply_field(field_name: String, field_type: ResourceGenerator.FieldType, default_value: Variant, element_type: int = -1) -> void:
	field_name_edit.text = field_name
	current_type = field_type

	# Set type dropdown
	for i in range(field_type_option.item_count):
		if field_type_option.get_item_id(i) == field_type:
			field_type_option.selected = i
			break

	# Set element type dropdown
	element_type_container.visible = (current_type == ResourceGenerator.FieldType.ARRAY)
	if element_type >= 0:
		current_element_type = element_type
		for i in range(element_type_option.item_count):
			if element_type_option.get_item_id(i) == element_type:
				element_type_option.selected = i
				break

	_update_default_value_editor()
	_set_default_value(default_value)


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

	var default_val = _get_default_value()
	var data := {
		"name": name_text,
		"type": current_type,
		"default": default_val
	}

	if current_type == ResourceGenerator.FieldType.ARRAY:
		data["element_type"] = current_element_type

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
					return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
				return Vector3.ZERO

		ResourceGenerator.FieldType.COLOR:
			if default_value_edit is ColorPickerButton:
				return default_value_edit.color

		ResourceGenerator.FieldType.ARRAY:
			return []

		ResourceGenerator.FieldType.DICTIONARY:
			return {}

	return null
