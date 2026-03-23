@tool
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)

const PAGE_SIZE: int = 50

var global_classes_map: Array[Dictionary]
var class_to_path_map: Dictionary[String, String] = {}
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
	project_resource_classes = ProjectClassScanner.get_project_resource_classes(global_classes_map)

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
	refresh_view()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	refresh_view()


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


func refresh_view() -> void:
	if not _resolve_current_classes():
		return
	_scan_properties()
	_scan_resources()
	_restore_selection()
	_current_page = 0
	_emit_page_data()


# ── Private ────────────────────────────────────────────────────────────────────

func _resolve_current_classes() -> bool:
	if _current_class_name.is_empty():
		return false
	if _include_subclasses:
		current_class_names = ProjectClassScanner.get_descendant_classes(_current_class_name, _classes_parent_map)
	else:
		current_class_names = [_current_class_name]
	current_class_script = _get_class_script(_current_class_name)
	return true


func _scan_properties() -> void:
	subclasses_property_lists = {}
	for cls_name: String in current_class_names:
		var script_path: String = class_to_path_map.get(cls_name, "")
		if not script_path.is_empty():
			subclasses_property_lists[cls_name] = ProjectClassScanner.get_properties_from_script_path(script_path)

	var empty_props: Array[Dictionary] = []
	current_class_property_list = subclasses_property_lists.get(_current_class_name, empty_props)
	columns = ProjectClassScanner.unite_classes_properties(current_class_names, class_to_path_map)


func _scan_resources() -> void:
	var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	if root == null or not is_instance_valid(root):
		push_warning("VREStateManager: filesystem directory is not valid, skipping resource scan.")
		return
	resources = ProjectClassScanner.load_classed_resources_from_dir(current_class_names, root)


func _restore_selection() -> void:
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_last_anchor = resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())


func _rescan_resources_only() -> void:
	if _current_class_name.is_empty():
		return
	_scan_resources()
	_restore_selection()
	_emit_page_data_preserving_page()


func _page_count() -> int:
	if resources.is_empty():
		return 1
	return ceili(float(resources.size()) / float(PAGE_SIZE))


func _emit_page_data() -> void:
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, resources.size())
	data_changed.emit(resources.slice(start, end), columns)
	pagination_changed.emit(_current_page, _page_count())


func _emit_page_data_preserving_page() -> void:
	var max_page: int = _page_count() - 1
	if _current_page > max_page:
		_current_page = max_page
	_emit_page_data()


func _set_maps() -> void:
	global_classes_map = ProjectClassScanner.build_global_classes_map()
	_classes_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_classes_map)

	class_to_path_map.clear()
	for entry: Dictionary in global_classes_map:
		var cls: String = entry.get("class", "")
		var path: String = entry.get("path", "")
		if not cls.is_empty() and not path.is_empty():
			class_to_path_map[cls] = path


func _on_script_classes_updated() -> void:
	print("classes updated")
	_classes_update_pending = true
	%RescanDebounceTimer.start_debouncing(_handle_classes_updated)


func _handle_classes_updated() -> void:
	_classes_update_pending = false
	_set_maps()

	var previous_classes: Array[String] = project_resource_classes.duplicate()
	project_resource_classes = ProjectClassScanner.get_project_resource_classes(global_classes_map)

	# Re-save .tres files for classes that disappeared (handles renames: updates script_class header)
	var removed_classes: Array[String] = []
	for cls: String in previous_classes:
		if not project_resource_classes.has(cls):
			removed_classes.append(cls)
	if not removed_classes.is_empty():
		var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
		if root != null and is_instance_valid(root):
			var resources_to_update: Array[Resource] = (
				ProjectClassScanner.load_classed_resources_from_dir(removed_classes, root)
			)
			for res: Resource in resources_to_update:
				ResourceSaver.save(res, res.resource_path)

	# Nothing changed in the class list — only check for property changes
	if previous_classes == project_resource_classes:
		if not _current_class_name.is_empty():
			var new_props: Array[Dictionary] = _get_current_class_props()
			if new_props != current_class_property_list:
				project_classes_changed.emit(project_resource_classes)
				_scan_properties()
				# Resave resources to drop stale properties / pick up new ones
				for res: Resource in resources:
					ResourceSaver.save(res, res.resource_path)
				_restore_selection()
				_emit_page_data_preserving_page()
		return

	# Class list changed — always update the dropdown
	project_classes_changed.emit(project_resource_classes)

	if _current_class_name.is_empty():
		return

	# Current class no longer in list — check if it was renamed (same script path, new name)
	if not project_resource_classes.has(_current_class_name):
		var old_path: String = ""
		if current_class_script != null:
			old_path = current_class_script.resource_path
		var new_name: String = ""
		if not old_path.is_empty():
			for cls: String in class_to_path_map:
				if class_to_path_map[cls] == old_path:
					new_name = cls
					break
		if new_name.is_empty():
			_clear_view()
			return
		_current_class_name = new_name
		current_class_renamed.emit(new_name)
		refresh_view()
		return

	# Check if any of the currently browsed classes were added or removed
	for cls: String in current_class_names:
		if not previous_classes.has(cls) or not project_resource_classes.has(cls):
			refresh_view()
			return

	# Current class set is unchanged in the list — check if its properties changed
	var new_props: Array[Dictionary] = _get_current_class_props()
	if new_props != current_class_property_list:
		_scan_properties()
		_emit_page_data_preserving_page()


func _get_current_class_props() -> Array[Dictionary]:
	var script_path: String = class_to_path_map.get(_current_class_name, "")
	if not script_path.is_empty():
		return ProjectClassScanner.get_properties_from_script_path(script_path)
	var empty_props: Array[Dictionary] = []
	return empty_props


func _get_class_script(class_name_str: String) -> GDScript:
	var script_path: String = class_to_path_map.get(class_name_str, "")
	if not script_path.is_empty():
		return load(script_path)
	return null


func _clear_view() -> void:
	_current_class_name = ""
	current_class_names.clear()
	current_class_script = null
	var empty_props: Array[Dictionary] = []
	current_class_property_list = empty_props
	subclasses_property_lists.clear()
	columns.clear()
	resources.clear()
	selected_resources.clear()
	_selected_paths.clear()
	_last_anchor = -1
	_current_page = 0
	var empty_resources: Array[Resource] = []
	var empty_columns: Array[Dictionary] = []
	data_changed.emit(empty_resources, empty_columns)
	selection_changed.emit(empty_resources)
	pagination_changed.emit(0, 1)


func _on_filesystem_changed() -> void:
	print("fs changed ")
	if _classes_update_pending:
		return
	%RescanDebounceTimer.start_debouncing(_rescan_resources_only)
