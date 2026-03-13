@tool
class_name ResourceRow
extends Button

signal resource_row_selected(resource: Resource, shift_held: bool)
signal delete_requested(resource_path: String)

var resource: Resource
var columns: Array[Dictionary]
var _prop_labels: Dictionary = {}  # property_name → Label (only for properties this resource owns)
var _color_style: StyleBoxFlat


func _ready() -> void:
	_color_style = StyleBoxFlat.new()
	_color_style.corner_radius_top_left = 2
	_color_style.corner_radius_top_right = 2
	_color_style.corner_radius_bottom_left = 2
	_color_style.corner_radius_bottom_right = 2

	%DeleteBtn.pressed.connect(func(): delete_requested.emit(resource.resource_path))

	%FileNameLabel.text = resource.resource_path.get_file()
	%FileNameLabel.tooltip_text = resource.resource_path

	_build_field_labels()


func _build_field_labels() -> void:
	for child in %FieldsContainer.get_children():
		child.queue_free()
	_prop_labels.clear()

	# Map which properties this resource's script actually declares
	var owned: Dictionary = {}
	if resource and resource.get_script():
		for p: Dictionary in resource.get_script().get_script_property_list():
			owned[p.name] = true

	for i: int in range(columns.size()):
		if i > 0:
			var sep: VSeparator = VSeparator.new()
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			%FieldsContainer.add_child(sep)

		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var col_name: String = columns[i].name
		if owned.has(col_name):
			_prop_labels[col_name] = label
			_set_label_value(label, columns[i])
		# else: label stays blank — belongs to a sibling subclass

		%FieldsContainer.add_child(label)


func update_display() -> void:
	if not resource:
		return
	for col: Dictionary in columns:
		if _prop_labels.has(col.name):
			_set_label_value(_prop_labels[col.name], col)


func is_selected() -> bool:
	return button_pressed


func set_selected(selected: bool) -> void:
	button_pressed = selected


func get_resource() -> Resource:
	return resource


func get_resource_path() -> String:
	return resource.resource_path


func _set_label_value(label: Label, col: Dictionary) -> void:
	var value: Variant = resource.get(col.name)
	label.text = _format_value(value, col.type)
	label.tooltip_text = "%s: %s" % [col.name, label.text]

	if col.type == TYPE_COLOR and value is Color:
		_color_style.bg_color = value
		label.add_theme_stylebox_override("normal", _color_style.duplicate())
		label.add_theme_color_override("font_color",
			Color.BLACK if value.get_luminance() > 0.5 else Color.WHITE)
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


func _on_pressed() -> void:
	resource_row_selected.emit(resource, Input.is_key_pressed(KEY_SHIFT))
