@tool
extends Window

var _included_classes_names_paths: Array[Dictionary] = ProjectClassScanner.get_resource_classes_in_folder([],[]) :
	set(new_value):
		_included_classes_names_paths = new_value
		if is_node_ready():
			set_class_selector_class_names()

func set_class_selector_class_names():
	var class_names: Array
	class_names = _included_classes_names_paths \
		.map(func(class_name_and_path): return class_name_and_path.name as String)
	print(class_names)
	%ClassSelector._classes_names = class_names

func _ready() -> void:
	set_class_selector_class_names()
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


func _on_class_selected(class_name_str: String) -> void:
	%ResourceList.set_resource_class(class_name_str)


func _on_filesystem_changed() -> void:
	%ResourceList.refresh()
	%ClassSelector.refresh()


func _on_close_requested() -> void:
	queue_free()
