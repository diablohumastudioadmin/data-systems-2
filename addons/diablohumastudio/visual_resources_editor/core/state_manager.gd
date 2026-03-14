@tool
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])
signal project_classes_changed(added: Array[String], removed: Array[String])

var _global_clases_map: Array[Dictionary]
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
	if efs and not efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.connect(_on_filesystem_changed)

	%RescanDebounceTimer.timeout.connect(_on_rescan_debounce_timeout)


func _exit_tree() -> void:
	if not Engine.is_editor_hint(): return

	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)

	if  %RescanDebounceTimer.timeout.is_connected(_on_rescan_debounce_timeout):
		%RescanDebounceTimer.timeout.disconnect(_on_rescan_debounce_timeout)


func set_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	rescan()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	rescan()


func rescan() -> void:
	if _current_class_name.is_empty():
		return

	_set_maps()
	_check_project_classes_changed()

	_current_class_names = _get_included_classes()

	columns = ProjectClassScanner.unite_classes_properties(_current_class_names, _global_clases_map)

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
	_global_clases_map = ProjectClassScanner.build_global_classes_map()
	_classes_parent_map = ProjectClassScanner.build_project_classes_parent_map(_global_clases_map)


func _check_project_classes_changed() -> void:
	var new_classes: Array[String] = ProjectClassScanner.get_resource_classes_in_folder(
		_classes_parent_map)
	if new_classes == project_resource_classes:
		return
	var added: Array[String] = []
	for cls: String in new_classes:
		if not project_resource_classes.has(cls):
			added.append(cls)
	var removed: Array[String] = []
	for cls: String in project_resource_classes:
		if not new_classes.has(cls):
			removed.append(cls)
	project_resource_classes = new_classes
	project_classes_changed.emit(added, removed)


func _get_included_classes() -> Array[String]:
	if not _include_subclasses: return [_current_class_name]
	else: return ProjectClassScanner.get_descendant_classes(_current_class_name, _classes_parent_map)


func _on_filesystem_changed() -> void:
	%RescanDebounceTimer.start()


func _on_rescan_debounce_timeout() -> void:
	rescan()
