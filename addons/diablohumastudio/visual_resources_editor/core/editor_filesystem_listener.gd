@tool
class_name EditorFileSystemListener
extends RefCounted

signal classes_changed()
signal filesystem_changed()

var _prevent_fs_changed: bool = false

func start() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if not efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.connect(_on_script_classes_updated)
		if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)


func stop() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.disconnect(_on_script_classes_updated)
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)


func _on_script_classes_updated() -> void:
	_prevent_fs_changed = true
	classes_changed.emit()


func _on_filesystem_changed() -> void:
	if _prevent_fs_changed:
		_prevent_fs_changed = false
		return
	filesystem_changed.emit()
