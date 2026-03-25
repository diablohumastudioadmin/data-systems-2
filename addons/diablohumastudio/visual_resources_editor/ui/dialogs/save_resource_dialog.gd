@tool
class_name SaveResourceDialog
extends EditorFileDialog

signal error_occurred(message: String)

var current_class_name: String = ""
var global_class_map: Array[Dictionary] = []


func _ready() -> void:
	filters = PackedStringArray(["*.tres"])
	file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_selected.connect(_on_file_selected)


func show_create_dialog() -> void:
	if current_class_name.is_empty():
		return
	if _get_class_script_path(current_class_name).is_empty():
		return
	title = "Save New %s" % current_class_name
	popup_centered(Vector2i(800, 500))


func _on_file_selected(path: String) -> void:
	var script_path: String = _get_class_script_path(current_class_name)
	var script: GDScript = load(script_path)
	if script == null:
		error_occurred.emit("Failed to load script for %s." % current_class_name)
		return
	if not script.can_instantiate():
		error_occurred.emit(
			"Can't instantiate %s.\nCheck its constructor." % current_class_name)
		return
	var instance: Resource = script.new()
	var err: Error = ResourceSaver.save(instance, path)
	if err != OK:
		error_occurred.emit("Failed to save resource:\n%s" % path)
		return


func _get_class_script_path(class_name_str: String) -> String:
	for entry: Dictionary in global_class_map:
		if entry.get("class", "") == class_name_str:
			return entry.get("path", "")
	return ""
