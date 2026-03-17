@tool
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])
signal project_classes_changed(classes: Array[String])

var global_clases_map: Array[Dictionary]
var _classes_parent_map: Dictionary[String, String]

var _current_class_name: String = ""
var _current_class_names: Array[String] = []
var _include_subclasses: bool = true

var project_resource_classes: Array[String] = ProjectClassScanner.get_resource_classes_in_folder()

var columns: Array[Dictionary] = []
var resources: Array[Resource] = []

func _ready() -> void:
	if not Engine.is_editor_hint(): return

	_set_maps()

	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)
		if not efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.connect(_on_script_classes_updated)

func _exit_tree() -> void:
	if not Engine.is_editor_hint(): return

	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)
		if efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.disconnect(_on_script_classes_updated)

func set_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	rescan()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	rescan()


func rescan() -> void:
	if _current_class_name.is_empty():
		return

	_current_class_names = _get_included_classes()

	columns = ProjectClassScanner.unite_classes_properties(_current_class_names, global_clases_map)

	var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	resources = ProjectClassScanner.load_classed_resources_from_dir(_current_class_names, root)

	data_changed.emit(resources, columns)


func get_class_names():
	return _current_class_names

func get_columns():
	return columns

func get_resources():
	return resources

# ── Private ────────────────────────────────────────────────────────────────────
func _set_maps() -> void:
	global_clases_map = ProjectClassScanner.build_global_classes_map()
	_classes_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_clases_map)


func _on_script_classes_updated() -> void:
	_set_maps()
	project_resource_classes = ProjectClassScanner.get_resource_classes_in_folder(_classes_parent_map)
	project_classes_changed.emit(project_resource_classes)
	rescan()


func _get_included_classes() -> Array[String]:
	if not _include_subclasses: return [_current_class_name]
	return ProjectClassScanner.get_descendant_classes(_current_class_name, _classes_parent_map)


func _on_filesystem_changed() -> void:
	%RescanDebounceTimer.start_debouncing(rescan)
