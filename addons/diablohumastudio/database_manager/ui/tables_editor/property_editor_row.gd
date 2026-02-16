@tool
extends HBoxContainer

## Reusable property editor row for TablesEditor (scene-based).
## Shows: Name | PropertyName | Type | PropertyType | Default: | [editor] | X

signal remove_requested()

@onready var property_name_edit: LineEdit = %PropertyNameEdit
@onready var property_type_option: OptionButton = %PropertyTypeOption
@onready var default_value_container: HBoxContainer = %DefaultValueContainer
@onready var remove_btn: Button = %RemoveBtn

var default_value_edit: Control  # Current editor inside DefaultValueContainer
var current_type: ResourceGenerator.PropertyType = ResourceGenerator.PropertyType.STRING

## Deferred initial data (set before _ready via set_property)
var _deferred_name: String = ""
var _deferred_type: ResourceGenerator.PropertyType = ResourceGenerator.PropertyType.STRING
var _deferred_default: Variant = null
var _has_deferred_data: bool = false


func _ready() -> void:
	_populate_type_options()
	property_type_option.item_selected.connect(_on_type_changed)
	remove_btn.pressed.connect(func(): remove_requested.emit())

	if _has_deferred_data:
		_apply_deferred_data()
	else:
		_update_default_value_editor()


func _populate_type_options() -> void:
	property_type_option.clear()
	property_type_option.add_item("int", ResourceGenerator.PropertyType.INT)
	property_type_option.add_item("float", ResourceGenerator.PropertyType.FLOAT)
	property_type_option.add_item("String", ResourceGenerator.PropertyType.STRING)
	property_type_option.add_item("bool", ResourceGenerator.PropertyType.BOOL)
	property_type_option.add_item("Texture2D", ResourceGenerator.PropertyType.TEXTURE2D)
	property_type_option.add_item("Vector2", ResourceGenerator.PropertyType.VECTOR2)
	property_type_option.add_item("Vector3", ResourceGenerator.PropertyType.VECTOR3)
	property_type_option.add_item("Color", ResourceGenerator.PropertyType.COLOR)
	property_type_option.add_item("Array", ResourceGenerator.PropertyType.ARRAY)
	property_type_option.add_item("Dictionary", ResourceGenerator.PropertyType.DICTIONARY)


func _update_default_value_editor() -> void:
	# Clear previous editor
	for child in default_value_container.get_children():
		child.queue_free()

	# Create new editor based on current type
	var editor: Control
	match current_type:
		ResourceGenerator.PropertyType.INT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 1
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.PropertyType.FLOAT:
			var spin = SpinBox.new()
			spin.min_value = -999999
			spin.max_value = 999999
			spin.step = 0.01
			spin.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = spin

		ResourceGenerator.PropertyType.STRING:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "default value"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.PropertyType.BOOL:
			var check_box = CheckBox.new()
			editor = check_box

		ResourceGenerator.PropertyType.TEXTURE2D:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "res://path/to/texture.png"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.PropertyType.VECTOR2:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.PropertyType.VECTOR3:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0, 0"
			line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			editor = line_edit

		ResourceGenerator.PropertyType.COLOR:
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
	current_type = property_type_option.get_item_id(index) as ResourceGenerator.PropertyType
	_update_default_value_editor()


func set_property(prop_name: String, prop_type: ResourceGenerator.PropertyType, default_value: Variant) -> void:
	# If not ready yet, defer the data
	if not is_node_ready():
		_deferred_name = prop_name
		_deferred_type = prop_type
		_deferred_default = default_value
		_has_deferred_data = true
		return

	_apply_property(prop_name, prop_type, default_value)


func _apply_deferred_data() -> void:
	_apply_property(_deferred_name, _deferred_type, _deferred_default)
	_has_deferred_data = false


func _apply_property(prop_name: String, prop_type: ResourceGenerator.PropertyType, default_value: Variant) -> void:
	property_name_edit.text = prop_name
	current_type = prop_type

	# Set type dropdown
	for i in range(property_type_option.item_count):
		if property_type_option.get_item_id(i) == prop_type:
			property_type_option.selected = i
			break

	_update_default_value_editor()
	_set_default_value(default_value)


func _set_default_value(value: Variant) -> void:
	if not default_value_edit:
		return

	match current_type:
		ResourceGenerator.PropertyType.INT, ResourceGenerator.PropertyType.FLOAT:
			if default_value_edit is SpinBox:
				default_value_edit.value = value if value != null else 0

		ResourceGenerator.PropertyType.STRING:
			if default_value_edit is LineEdit:
				default_value_edit.text = value if value != null else ""

		ResourceGenerator.PropertyType.BOOL:
			if default_value_edit is CheckBox:
				default_value_edit.button_pressed = value if value != null else false

		ResourceGenerator.PropertyType.TEXTURE2D:
			if default_value_edit is LineEdit:
				if value is Texture2D:
					default_value_edit.text = value.resource_path
				elif value is String:
					default_value_edit.text = value

		ResourceGenerator.PropertyType.VECTOR2:
			if default_value_edit is LineEdit and value is Vector2:
				default_value_edit.text = "%f, %f" % [value.x, value.y]

		ResourceGenerator.PropertyType.VECTOR3:
			if default_value_edit is LineEdit and value is Vector3:
				default_value_edit.text = "%f, %f, %f" % [value.x, value.y, value.z]

		ResourceGenerator.PropertyType.COLOR:
			if default_value_edit is ColorPickerButton:
				default_value_edit.color = value if value is Color else Color.WHITE


func get_property_data() -> Dictionary:
	var prop_name = property_name_edit.text.strip_edges()
	if prop_name.is_empty():
		return {}

	var default_val = _get_default_value()

	return {
		"name": prop_name,
		"type": current_type,
		"default": default_val
	}


func _get_default_value() -> Variant:
	if not default_value_edit:
		return null

	match current_type:
		ResourceGenerator.PropertyType.INT, ResourceGenerator.PropertyType.FLOAT:
			if default_value_edit is SpinBox:
				return default_value_edit.value

		ResourceGenerator.PropertyType.STRING:
			if default_value_edit is LineEdit:
				return default_value_edit.text

		ResourceGenerator.PropertyType.BOOL:
			if default_value_edit is CheckBox:
				return default_value_edit.button_pressed

		ResourceGenerator.PropertyType.TEXTURE2D:
			if default_value_edit is LineEdit:
				var path = default_value_edit.text.strip_edges()
				if path.is_empty():
					return null
				return path

		ResourceGenerator.PropertyType.VECTOR2:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
				return Vector2.ZERO

		ResourceGenerator.PropertyType.VECTOR3:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 3:
					return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
				return Vector3.ZERO

		ResourceGenerator.PropertyType.COLOR:
			if default_value_edit is ColorPickerButton:
				return default_value_edit.color

		ResourceGenerator.PropertyType.ARRAY:
			return []

		ResourceGenerator.PropertyType.DICTIONARY:
			return {}

	return null
