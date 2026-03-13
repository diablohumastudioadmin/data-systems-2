@tool
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])

var _current_class_name: String = ""
var _include_subclasses: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if efs:
			efs.filesystem_changed.connect(_on_filesystem_changed)
	%RescanDebounceTimer.timeout.connect(_on_rescan_debounce_timeout)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
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
	var classes: Array[String] = _get_included_classes()
	var columns: Array[Dictionary] = _compute_union_columns(classes)
	var resources: Array[Resource] = _load_resources(classes)
	data_changed.emit(resources, columns)


# ── Private ────────────────────────────────────────────────────────────────────

func _get_included_classes() -> Array[String]:
	var classes: Array[String] = [_current_class_name]
	if _include_subclasses:
		classes.append_array(
			ProjectClassScanner.get_descendant_classes(_current_class_name)
		)
	return classes


func _compute_union_columns(classes: Array[String]) -> Array[Dictionary]:
	var class_to_path: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		var path: String = entry.get("path", "")
		if not cls.is_empty() and not path.is_empty():
			class_to_path[cls] = path

	var seen: Dictionary = {}
	var columns: Array[Dictionary] = []
	for cls_name: String in classes:
		var script_path: String = class_to_path.get(cls_name, "")
		if script_path.is_empty():
			continue
		for prop: Dictionary in ProjectClassScanner.get_properties_from_script_path(script_path):
			if not seen.has(prop.name):
				seen[prop.name] = true
				columns.append(prop)
	return columns


func _load_resources(classes: Array[String]) -> Array[Resource]:
	var root: EditorFileSystemDirectory = EditorInterface \
		.get_resource_filesystem().get_filesystem()
	var paths: Array[String] = ProjectClassScanner.scan_folder_for_classed_tres(root, classes)
	paths.sort()
	var resources: Array[Resource] = []
	for path: String in paths:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res:
			resources.append(res)
	return resources


func _on_filesystem_changed() -> void:
	%RescanDebounceTimer.start()


func _on_rescan_debounce_timeout() -> void:
	rescan()
