@tool
extends HBoxContainer

var columns: Array[Dictionary] = []:
	set(value):
		columns = value
		if is_inside_tree():
			_rebuild_labels()


func _rebuild_labels() -> void:
	for child in %FieldsContainer.get_children():
		child.queue_free()

	for i in range(columns.size()):
		if i > 0:
			var sep: VSeparator = VSeparator.new()
			%FieldsContainer.add_child(sep)
		var lbl: Label = Label.new()
		lbl.text = columns[i].name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 12)
		%FieldsContainer.add_child(lbl)
