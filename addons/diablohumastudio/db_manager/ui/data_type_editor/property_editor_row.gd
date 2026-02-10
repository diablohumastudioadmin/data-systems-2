
@tool
extends HBoxContainer

## Reusable property editor row for DataTypeEditor
## Shows: Property Name | Type | Default Value | Remove Button

signal remove_requested()

var property_name_edit: LineEdit
var property_type_option: OptionButton
var default_value_edit: Control  # Changes based on type
var remove_btn: Button

var current_type: DataTypeDefinition.PropertyType = DataTypeDefinition.PropertyType.STRING


func _init() -> void:
	_create_ui()


func _create_ui() -> void:
	# Property name
	var name_label = Label.new()
	name_label.text = "Name:"
	name_label.custom_minimum_size = Vector2(50, 0)
	add_child(name_label)

	property_name_edit = LineEdit.new()
	property_name_edit.placeholder_text = "property_name"
	property_name_edit.custom_minimum_size = Vector2(150, 0)
	property_name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(property_name_edit)

	# Property type
	var type_label = Label.new()
	type_label.text = "Type:"
	type_label.custom_minimum_size = Vector2(40, 0)
	add_child(type_label)

	property_type_option = OptionButton.new()
	property_type_option.custom_minimum_size = Vector2(120, 0)
	_populate_type_options()
	property_type_option.item_selected.connect(_on_type_changed)
	add_child(property_type_option)

	# Default value (will be created based on type)
	_create_default_value_editor()

	# Remove button
	remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func(): remove_requested.emit())
	add_child(remove_btn)


func _populate_type_options() -> void:
	property_type_option.clear()
	property_type_option.add_item("int", DataTypeDefinition.PropertyType.INT)
	property_type_option.add_item("float", DataTypeDefinition.PropertyType.FLOAT)
	property_type_option.add_item("String", DataTypeDefinition.PropertyType.STRING)
	property_type_option.add_item("bool", DataTypeDefinition.PropertyType.BOOL)
	property_type_option.add_item("Texture2D", DataTypeDefinition.PropertyType.TEXTURE2D)
	property_type_option.add_item("Vector2", DataTypeDefinition.PropertyType.VECTOR2)
	property_type_option.add_item("Vector3", DataTypeDefinition.PropertyType.VECTOR3)
	property_type_option.add_item("Color", DataTypeDefinition.PropertyType.COLOR)
	property_type_option.add_item("Array", DataTypeDefinition.PropertyType.ARRAY)
	property_type_option.add_item("Dictionary", DataTypeDefinition.PropertyType.DICTIONARY)


func _create_default_value_editor() -> void:
	if default_value_edit:
		default_value_edit.queue_free()

	var label = Label.new()
	label.text = "Default:"
	label.custom_minimum_size = Vector2(60, 0)
	add_child(label)

	match current_type:
		DataTypeDefinition.PropertyType.INT:
			var spin_box = SpinBox.new()
			spin_box.min_value = -999999
			spin_box.max_value = 999999
			spin_box.step = 1
			spin_box.custom_minimum_size = Vector2(100, 0)
			default_value_edit = spin_box

		DataTypeDefinition.PropertyType.FLOAT:
			var spin_box = SpinBox.new()
			spin_box.min_value = -999999
			spin_box.max_value = 999999
			spin_box.step = 0.01
			spin_box.custom_minimum_size = Vector2(100, 0)
			default_value_edit = spin_box

		DataTypeDefinition.PropertyType.STRING:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "default value"
			line_edit.custom_minimum_size = Vector2(150, 0)
			default_value_edit = line_edit

		DataTypeDefinition.PropertyType.BOOL:
			var check_box = CheckBox.new()
			default_value_edit = check_box

		DataTypeDefinition.PropertyType.TEXTURE2D:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "res://path/to/texture.png"
			line_edit.custom_minimum_size = Vector2(200, 0)
			default_value_edit = line_edit

		DataTypeDefinition.PropertyType.VECTOR2, DataTypeDefinition.PropertyType.VECTOR3:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "0, 0" if current_type == DataTypeDefinition.PropertyType.VECTOR2 else "0, 0, 0"
			line_edit.custom_minimum_size = Vector2(120, 0)
			default_value_edit = line_edit

		DataTypeDefinition.PropertyType.COLOR:
			var color_picker = ColorPickerButton.new()
			color_picker.custom_minimum_size = Vector2(80, 0)
			default_value_edit = color_picker

		_:
			var line_edit = LineEdit.new()
			line_edit.placeholder_text = "{} or []"
			line_edit.custom_minimum_size = Vector2(100, 0)
			default_value_edit = line_edit

	add_child(default_value_edit)


func _on_type_changed(index: int) -> void:
	current_type = property_type_option.get_item_id(index) as DataTypeDefinition.PropertyType

	# Recreate default value editor for new type
	if default_value_edit:
		remove_child(default_value_edit)
		default_value_edit.queue_free()

	_create_default_value_editor()


func set_property(prop_name: String, prop_type: DataTypeDefinition.PropertyType, default_value: Variant) -> void:
	property_name_edit.text = prop_name
	current_type = prop_type

	# Set type dropdown
	for i in range(property_type_option.item_count):
		if property_type_option.get_item_id(i) == prop_type:
			property_type_option.selected = i
			break

	# Recreate default value editor
	if default_value_edit:
		remove_child(default_value_edit)
		default_value_edit.queue_free()

	_create_default_value_editor()

	# Set default value
	_set_default_value(default_value)


func _set_default_value(value: Variant) -> void:
	if !default_value_edit:
		return

	match current_type:
		DataTypeDefinition.PropertyType.INT, DataTypeDefinition.PropertyType.FLOAT:
			if default_value_edit is SpinBox:
				default_value_edit.value = value if value != null else 0

		DataTypeDefinition.PropertyType.STRING:
			if default_value_edit is LineEdit:
				default_value_edit.text = value if value != null else ""

		DataTypeDefinition.PropertyType.BOOL:
			if default_value_edit is CheckBox:
				default_value_edit.button_pressed = value if value != null else false

		DataTypeDefinition.PropertyType.TEXTURE2D:
			if default_value_edit is LineEdit:
				if value is Texture2D:
					default_value_edit.text = value.resource_path
				elif value is String:
					default_value_edit.text = value

		DataTypeDefinition.PropertyType.VECTOR2:
			if default_value_edit is LineEdit and value is Vector2:
				default_value_edit.text = "%f, %f" % [value.x, value.y]

		DataTypeDefinition.PropertyType.VECTOR3:
			if default_value_edit is LineEdit and value is Vector3:
				default_value_edit.text = "%f, %f, %f" % [value.x, value.y, value.z]

		DataTypeDefinition.PropertyType.COLOR:
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
	if !default_value_edit:
		return null

	match current_type:
		DataTypeDefinition.PropertyType.INT, DataTypeDefinition.PropertyType.FLOAT:
			if default_value_edit is SpinBox:
				return default_value_edit.value

		DataTypeDefinition.PropertyType.STRING:
			if default_value_edit is LineEdit:
				return default_value_edit.text

		DataTypeDefinition.PropertyType.BOOL:
			if default_value_edit is CheckBox:
				return default_value_edit.button_pressed

		DataTypeDefinition.PropertyType.TEXTURE2D:
			if default_value_edit is LineEdit:
				var path = default_value_edit.text.strip_edges()
				if path.is_empty():
					return null
				return path

		DataTypeDefinition.PropertyType.VECTOR2:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 2:
					return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
				return Vector2.ZERO

		DataTypeDefinition.PropertyType.VECTOR3:
			if default_value_edit is LineEdit:
				var parts = default_value_edit.text.split(",")
				if parts.size() >= 3:
					return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
				return Vector3.ZERO

		DataTypeDefinition.PropertyType.COLOR:
			if default_value_edit is ColorPickerButton:
				return default_value_edit.color

		DataTypeDefinition.PropertyType.ARRAY:
			return []

		DataTypeDefinition.PropertyType.DICTIONARY:
			return {}

	return null
