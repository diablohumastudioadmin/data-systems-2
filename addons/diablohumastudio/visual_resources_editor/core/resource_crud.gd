@tool
class_name ResourceCRUD
extends Node

const SAVE_RESOURCE_DIALOG_SCENE: PackedScene = preload("uid://87kt88zgjkg7p")
const CONFIRM_DELETE_DIALOG_SCENE: PackedScene = preload("uid://m55213yow13bd")
const ERROR_DIALOG_SCENE: PackedScene = preload("uid://9g7t37gm0qcdf")

var current_class_name: String = ""


func create() -> void:
	if current_class_name.is_empty():
		return
	var script_path: String = _get_class_script_path(current_class_name)
	if script_path.is_empty():
		return

	var dialog: EditorFileDialog = SAVE_RESOURCE_DIALOG_SCENE.instantiate()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres")
	dialog.title = "Save New %s" % current_class_name
	dialog.file_selected.connect(func(path: String) -> void:
		var target_path: String = _normalize_tres_path(path)
		var script: GDScript = load(script_path)
		if script == null:
			_show_error("Failed to load script for %s." % current_class_name)
			dialog.queue_free()
			return
		if not script.can_instantiate():
			_show_error("Can't instantiate %s.\nCheck its constructor." % current_class_name)
			dialog.queue_free()
			return
		var instance: Resource = script.new()
		var err: Error = ResourceSaver.save(instance, target_path)
		if err != OK:
			_show_error("Failed to save resource:\n%s" % target_path)
			dialog.queue_free()
			return
		EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	get_parent().add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


func delete(paths: Array[String]) -> void:
	var dialog: ConfirmationDialog = CONFIRM_DELETE_DIALOG_SCENE.instantiate()
	dialog.dialog_text = "Delete %d resource(s)?\nThis cannot be undone.\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p: String) -> String: return p.get_file()))
	]
	dialog.confirmed.connect(func() -> void:
		var failed_paths: Array[String] = []
		for path: String in paths:
			var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if err != OK:
				failed_paths.append(path)
		EditorInterface.get_resource_filesystem().scan()
		if not failed_paths.is_empty():
			_show_error("Failed to delete:\n%s" % "\n".join(failed_paths))
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


func _normalize_tres_path(path: String) -> String:
	if path.ends_with(".tres"):
		return path
	return "%s.tres" % path


func _show_error(message: String) -> void:
	var dialog: AcceptDialog = ERROR_DIALOG_SCENE.instantiate()
	dialog.dialog_text = message
	get_parent().add_child(dialog)
	dialog.popup_centered()
