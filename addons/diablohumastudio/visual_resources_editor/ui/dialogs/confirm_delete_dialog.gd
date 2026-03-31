@tool
class_name ConfirmDeleteDialog
extends ConfirmationDialog

signal error_occurred(message: String)

var _pending_paths: Array[String] = []

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()
	confirmed.connect(_on_confirmed)


func _connect_state():
	state_manager.delete_selected_requested.connect(on_state_manager_delete_selected_requested)


func on_state_manager_delete_selected_requested(paths: Array[String]):
	show_delete_dialog(paths)


func show_delete_dialog(paths: Array[String]) -> void:
	_pending_paths = paths
	dialog_text = "Move %d resource(s) to trash?\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p: String) -> String: return p.get_file()))
	]
	popup_centered()


func _on_confirmed() -> void:
	var failed_paths: Array[String] = []
	for path: String in _pending_paths:
		# Guard: only delete files inside the project to prevent accidental
		# deletion of arbitrary filesystem paths via a malformed resource_path.
		if not path.begins_with("res://"):
			push_warning("VRE: Skipping delete of path outside project: %s" % path)
			failed_paths.append(path)
			continue
		var err: Error = OS.move_to_trash(ProjectSettings.globalize_path(path))
		if err != OK:
			failed_paths.append(path)
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	for path: String in _pending_paths:
		efs.update_file(path)
	if not failed_paths.is_empty():
		error_occurred.emit("Failed to delete:\n%s" % "\n".join(failed_paths))
	_pending_paths.clear()
