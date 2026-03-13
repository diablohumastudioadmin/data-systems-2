@tool
class_name ResourceCRUD
extends Node

var current_class_name: String = ""


func create() -> void:
	if current_class_name.is_empty():
		return
	var script_path: String = _get_class_script_path(current_class_name)
	if script_path.is_empty():
		return

	var dialog: EditorFileDialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres")
	dialog.title = "Save New %s" % current_class_name
	dialog.file_selected.connect(func(path: String) -> void:
		var script: GDScript = load(script_path)
		if script:
			ResourceSaver.save(script.new(), path)
			EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	get_parent().add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


func delete(paths: Array[String]) -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete %d resource(s)?\nThis cannot be undone.\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p: String) -> String: return p.get_file()))
	]
	dialog.confirmed.connect(func() -> void:
		for path: String in paths:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	get_parent().add_child(dialog)
	dialog.popup_centered()


func _get_class_script_path(class_name_str: String) -> String:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == class_name_str:
			return entry.get("path", "")
	return ""
