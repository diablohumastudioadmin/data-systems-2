@tool
extends HBoxContainer

signal row_clicked(resource_path: String)
signal row_selected(resource_path: String, is_selected: bool)
signal delete_requested(resource_path: String)

var _resource: Resource
var _resource_path: String
var _columns: Array[Dictionary]
var _field_labels: Array[Label] = []

var _normal_style: StyleBoxFlat
var _highlight_style: StyleBoxFlat


func _ready() -> void:
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color.TRANSPARENT

	_highlight_style = StyleBoxFlat.new()
	_highlight_style.bg_color = Color(0.2, 0.4, 0.7, 0.3)
	_highlight_style.corner_radius_top_left = 4
	_highlight_style.corner_radius_top_right = 4
	_highlight_style.corner_radius_bottom_left = 4
	_highlight_style.corner_radius_bottom_right = 4

	add_theme_stylebox_override("panel", _normal_style)

	%SelectCheck.toggled.connect(_on_check_toggled)
	%DeleteBtn.pressed.connect(func(): delete_requested.emit(_resource_path))


func setup(resource: Resource, columns: Array[Dictionary]) -> void:
	_resource = resource
	_resource_path = resource.resource_path
	_columns = columns

	%FileNameLabel.text = _resource_path.get_file()
	%FileNameLabel.tooltip_text = _resource_path

	_build_field_labels()


func _build_field_labels() -> void:
	for child in %FieldsContainer.get_children():
		child.queue_free()
	_field_labels.clear()

	for col: Dictionary in _columns:
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_set_label_value(label, col)
		%FieldsContainer.add_child(label)
		_field_labels.append(label)


func update_display() -> void:
	if not _resource:
		return
	for i in range(_columns.size()):
		if i < _field_labels.size():
			_set_label_value(_field_labels[i], _columns[i])


func set_highlighted(highlighted: bool) -> void:
	add_theme_stylebox_override("panel", _highlight_style if highlighted else _normal_style)


func get_resource() -> Resource:
	return _resource


func get_resource_path() -> String:
	return _resource_path


func is_checked() -> bool:
	return %SelectCheck.button_pressed


func set_checked(checked: bool) -> void:
	%SelectCheck.button_pressed = checked


func _set_label_value(label: Label, col: Dictionary) -> void:
	var value: Variant = _resource.get(col.name)
	label.text = _format_value(value, col.type)
	label.tooltip_text = "%s: %s" % [col.name, label.text]

	# Color swatch
	if col.type == TYPE_COLOR and value is Color:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = value
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
		label.add_theme_stylebox_override("normal", sb)
		label.add_theme_color_override("font_color",
			Color.BLACK if value.v > 0.5 else Color.WHITE)
	else:
		label.remove_theme_stylebox_override("normal")
		label.remove_theme_color_override("font_color")


func _format_value(value: Variant, type: int) -> String:
	if value == null:
		return "<null>"
	match type:
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_OBJECT:
			if value is Resource and not value.resource_path.is_empty():
				return value.resource_path.get_file()
			return str(value)
		TYPE_VECTOR2:
			return "(%g, %g)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "(%g, %g, %g)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return value.to_html()
	return str(value)


func _on_check_toggled(pressed: bool) -> void:
	row_selected.emit(_resource_path, pressed)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		row_clicked.emit(_resource_path)
