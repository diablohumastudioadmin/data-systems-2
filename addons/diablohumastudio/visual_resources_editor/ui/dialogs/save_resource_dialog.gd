@tool
class_name SaveResourceDialog
extends EditorFileDialog

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()
	filters = PackedStringArray(["*.tres"])
	file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_selected.connect(_on_file_selected)

func _connect_state():
	state_manager.create_new_resource_requested.connect(on_state_manager_create_new_resource_requested)

func on_state_manager_create_new_resource_requested():
	show_create_dialog()

func show_create_dialog() -> void:
	if state_manager.current_class_name.is_empty():
		return
	if _get_class_script_path(state_manager.current_class_name).is_empty():
		return
	title = "Save New %s" % state_manager.current_class_name
	popup_centered(Vector2i(800, 500))


func _on_file_selected(path: String) -> void:
	var script_path: String = _get_class_script_path(state_manager.current_class_name)
	var script: GDScript = load(script_path)
	if script == null:
		state_manager.report_error("Failed to load script for %s." % state_manager.current_class_name)
		return
	if not script.can_instantiate():
		state_manager.report_error(
			"Can't instantiate %s.\nCheck its constructor." % state_manager.current_class_name)
		return
	var instance: Resource = script.new()
	var err: Error = ResourceSaver.save(instance, path)
	if err != OK:
		state_manager.report_error("Failed to save resource:\n%s" % path)
		return


func _get_class_script_path(class_name_str: String) -> String:
	for entry: Dictionary in state_manager.global_class_map:
		if entry.get("class", "") == class_name_str:
			return entry.get("path", "")
	return ""
