@tool
class_name ResourceRow
extends Button

signal resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool)
signal delete_requested(resource_path: String)

const RESOURCE_FIELD_LABEL_SCENE: PackedScene = preload("uid://uru49vi0kvgxy")
const FIELD_SEPARATOR_SCENE: PackedScene = preload("uid://y2kj6h91hm8r6")

var resource: Resource = null
var columns: Array[Dictionary] = []
var _prop_labels: Dictionary = {}  # property_name → Label (only for properties this resource owns)


func _ready() -> void:
	if not resource: return
	
	%DeleteBtn.pressed.connect(_on_delete_pressed)
	%FileNameLabel.text = resource.resource_path.get_file()
	%FileNameLabel.tooltip_text = resource.resource_path

	_build_field_labels()


func _build_field_labels() -> void:
	for child: Node in %FieldsContainer.get_children():
		child.queue_free()
	_prop_labels.clear()

	# Map which editor-visible properties this resource's script actually declares
	# Uses the same filter as ProjectClassScanner.get_properties_from_script_path()
	var owned: Dictionary = {}
	if resource and resource.get_script():
		for p: Dictionary in resource.get_script().get_script_property_list():
			if not (p.usage & PROPERTY_USAGE_EDITOR):
				continue
			var pname: String = p.name
			if pname.begins_with("resource_") or pname.begins_with("metadata/"):
				continue
			if pname in ["script", "resource_local_to_scene"]:
				continue
			owned[pname] = true

	for i: int in columns.size():
		if not columns[i].has("name"):
			continue
		if i > 0:
			var sep: VSeparator = FIELD_SEPARATOR_SCENE.instantiate()
			%FieldsContainer.add_child(sep)

		var label: Label = RESOURCE_FIELD_LABEL_SCENE.instantiate()

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
		var style: StyleBoxFlat = label.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			style.bg_color = value
		label.add_theme_color_override("font_color",
			Color.BLACK if value.get_luminance() > 0.5 else Color.WHITE)
	else:
		var style: StyleBoxFlat = label.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			style.bg_color = Color.TRANSPARENT
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
	var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	resource_row_selected.emit(resource, ctrl_held, shift_held)


func _on_delete_pressed() -> void:
	if resource == null:
		return
	delete_requested.emit(resource.resource_path)
