@tool
class_name ResourceFieldLabel
extends Label


func set_value(resource: Resource, col: ResourceProperty) -> void:
	var value: Variant = resource.get(col.name)
	text = _format_value(value, col.type)
	tooltip_text = "%s: %s" % [col.name, text]

	if col.type == TYPE_COLOR and value is Color:
		var style: StyleBoxFlat = get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		if style:
			style.bg_color = value
			add_theme_stylebox_override("normal", style)
		add_theme_color_override("font_color",
			Color.BLACK if value.get_luminance() > 0.5 else Color.WHITE)
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_color_override("font_color")


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
