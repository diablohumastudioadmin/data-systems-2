@tool
class_name ComfirmDeleteDialog
extends ConfirmationDialog

signal error_occurred(message: String)

var _pending_paths: Array[String] = []


func _ready() -> void:
	confirmed.connect(_on_confirmed)


func show_delete_dialog(paths: Array[String]) -> void:
	_pending_paths = paths
	dialog_text = "Delete %d resource(s)?\nThis cannot be undone.\n\n%s" % [
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
		var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if err != OK:
			failed_paths.append(path)
	EditorInterface.get_resource_filesystem().scan()
	if not failed_paths.is_empty():
		error_occurred.emit("Failed to delete:\n%s" % "\n".join(failed_paths))
	_pending_paths.clear()
