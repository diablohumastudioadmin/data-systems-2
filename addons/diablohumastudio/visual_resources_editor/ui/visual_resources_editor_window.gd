@tool
extends Window


func _ready() -> void:
	%ClassSelector.class_selected.connect(_on_class_selected)

	if Engine.is_editor_hint():
		var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if efs and not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)


func _on_class_selected(class_name_str: String, script_path: String) -> void:
	%ResourceList.set_resource_class(class_name_str, script_path)


func _on_filesystem_changed() -> void:
	%ResourceList.refresh()


func _on_close_requested() -> void:
	queue_free()
