@tool
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)

const PAGE_SIZE: int = 50

var global_classes_map: Array[Dictionary]
var _classes_parent_map: Dictionary[String, String]

var _current_class_name: String = ""
var current_class_names: Array[String] = []
var _include_subclasses: bool = true

var project_resource_classes: Array[String] = []

var current_class_script: GDScript = null
var current_class_property_list: Array[Dictionary] = []
var subclasses_property_lists: Dictionary = {}
var columns: Array[Dictionary] = []
var resources: Array[Resource] = []

var selected_resources: Array[Resource] = []
var _selected_paths: Array[String] = []
var _last_anchor: int = -1
var _current_page: int = 0
var _classes_update_pending: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint(): return

	_set_maps()
	project_resource_classes = ProjectClassScanner.get_resource_classes_in_folder(_classes_parent_map)

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


func select(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	var current_idx: int = resources.find(resource)
	if shift_held and _last_anchor != -1 and current_idx != -1:
		selected_resources.clear()
		_selected_paths.clear()
		var from: int = mini(_last_anchor, current_idx)
		var to: int = maxi(_last_anchor, current_idx)
		for i: int in (to - from + 1):
			var res: Resource = resources[from + i]
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
		# anchor stays unchanged on shift+click
	elif ctrl_held:
		if selected_resources.has(resource):
			selected_resources.erase(resource)
			_selected_paths.erase(resource.resource_path)
		else:
			selected_resources.append(resource)
			_selected_paths.append(resource.resource_path)
		_last_anchor = current_idx
	else:
		selected_resources.clear()
		_selected_paths.clear()
		selected_resources.append(resource)
		_selected_paths.append(resource.resource_path)
		_last_anchor = current_idx
	selection_changed.emit(selected_resources.duplicate())


func next_page() -> void:
	if _current_page < _page_count() - 1:
		_current_page += 1
		_emit_page_data()


func prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_emit_page_data()


func rescan() -> void:
	if _current_class_name.is_empty():
		return

	current_class_names = _get_included_classes()
	if current_class_names.is_empty():
		push_warning("VREStateManager: class '%s' resolved to no classes. Was it deleted?" % _current_class_name)
		return
	current_class_script = _get_class_script(_current_class_name)

	var class_to_path: Dictionary = {}
	for entry: Dictionary in global_classes_map:
		var cls: String = entry.get("class", "")
		var path: String = entry.get("path", "")
		if not cls.is_empty() and not path.is_empty():
			class_to_path[cls] = path

	subclasses_property_lists = {}
	for cls_name: String in current_class_names:
		var script_path: String = class_to_path.get(cls_name, "")
		if not script_path.is_empty():
			subclasses_property_lists[cls_name] = ProjectClassScanner.get_properties_from_script_path(script_path)

	current_class_property_list = subclasses_property_lists.get(_current_class_name, [])

	columns = ProjectClassScanner.unite_classes_properties(current_class_names, global_classes_map)

	var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	if root == null or not is_instance_valid(root):
		push_warning("VREStateManager: filesystem directory is not valid, skipping resource scan.")
		return
	resources = ProjectClassScanner.load_classed_resources_from_dir(current_class_names, root)

	# Restore selection for resources that still exist after rescan
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_last_anchor = resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())

	_current_page = 0
	_emit_page_data()


# ── Private ────────────────────────────────────────────────────────────────────

func _page_count() -> int:
	if resources.is_empty():
		return 1
	return ceili(float(resources.size()) / float(PAGE_SIZE))


func _emit_page_data() -> void:
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, resources.size())
	data_changed.emit(resources.slice(start, end), columns)
	pagination_changed.emit(_current_page, _page_count())


func _set_maps() -> void:
	global_classes_map = ProjectClassScanner.build_global_classes_map()
	_classes_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_classes_map)


func _on_script_classes_updated() -> void:
	_classes_update_pending = true
	%RescanDebounceTimer.start_debouncing(_handle_classes_updated)


func _handle_classes_updated() -> void:
	_classes_update_pending = false
	_set_maps()

	var previous_classes: Array[String] = project_resource_classes.duplicate()
	project_resource_classes = ProjectClassScanner.get_resource_classes_in_folder(_classes_parent_map)

	# Nothing changed in the class list — check only for internal property changes
	if previous_classes == project_resource_classes:
		if not _current_class_name.is_empty():
			var new_props: Array[Dictionary] = _get_current_class_props()
			if new_props != current_class_property_list:
				project_classes_changed.emit(project_resource_classes)
				rescan()
		return

	# Class list changed — always update the dropdown
	project_classes_changed.emit(project_resource_classes)

	if _current_class_name.is_empty():
		return

	# Check if any of the currently browsed classes were added or removed
	for cls: String in current_class_names:
		if not previous_classes.has(cls) or not project_resource_classes.has(cls):
			rescan()
			return

	# Current class set is unchanged in the list — check if its properties changed
	var new_props: Array[Dictionary] = _get_current_class_props()
	if new_props != current_class_property_list:
		rescan()


func _get_current_class_props() -> Array[Dictionary]:
	for entry: Dictionary in global_classes_map:
		if entry.get("class", "") == _current_class_name:
			return ProjectClassScanner.get_properties_from_script_path(entry.get("path", ""))
	return []


func _get_included_classes() -> Array[String]:
	if not _include_subclasses: return [_current_class_name]
	return ProjectClassScanner.get_descendant_classes(_current_class_name, _classes_parent_map)


func _get_class_script(class_name_str: String) -> GDScript:
	for entry: Dictionary in global_classes_map:
		if entry.get("class", "") == class_name_str:
			return load(entry.get("path", ""))
	return null


func _on_filesystem_changed() -> void:
	if _classes_update_pending:
		return
	%RescanDebounceTimer.start_debouncing(rescan)
