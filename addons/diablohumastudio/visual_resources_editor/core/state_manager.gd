@tool
class_name VREStateManager
extends Node

signal resources_replaced(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)

const PAGE_SIZE: int = 50

var global_class_map: Array[Dictionary]
var global_class_to_path_map: Dictionary[String, String] = {}
var global_class_to_parent_map: Dictionary[String, String]
var global_class_name_list: Array[String] = []

var _include_subclasses: bool = true

var _current_class_name: String = ""
var _current_included_class_names: Array[String] = []

var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var current_included_class_property_lists: Dictionary = {}
var current_shared_propery_list: Array[ResourceProperty] = []

var current_resources: Array[Resource] = []
var _current_resource_mtimes: Dictionary[String, int] = {}

var selected_resources: Array[Resource] = []
var _selected_paths: Array[String] = []
var _selected_resources_last_index: int = -1

var _current_page: int = 0

var _classes_update_pending: bool = false

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


func set_current_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	refresh_resource_list_values()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	refresh_resource_list_values()


func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	var current_idx: int = current_resources.find(resource)
	if shift_held and _selected_resources_last_index != -1 and current_idx != -1:
		handle_select_shift(current_idx)
	elif ctrl_held:
		handle_select_ctrl(resource, current_idx)
	else:
		handle_select_no_key(resource, current_idx)
	selection_changed.emit(selected_resources.duplicate())


func handle_select_shift(current_idx: int) -> void:
	selected_resources.clear()
	_selected_paths.clear()
	var from: int = mini(_selected_resources_last_index, current_idx)
	var to: int = maxi(_selected_resources_last_index, current_idx)
	for i: int in (to - from + 1):
		var res: Resource = current_resources[from + i]
		selected_resources.append(res)
		_selected_paths.append(res.resource_path)
	# anchor stays unchanged on shift+click


func handle_select_ctrl(resource: Resource, current_idx: int) -> void:
	if selected_resources.has(resource):
		selected_resources.erase(resource)
		_selected_paths.erase(resource.resource_path)
	else:
		selected_resources.append(resource)
		_selected_paths.append(resource.resource_path)
	_selected_resources_last_index = current_idx


func handle_select_no_key(resource: Resource, current_idx: int) -> void:
	selected_resources.clear()
	_selected_paths.clear()
	selected_resources.append(resource)
	_selected_paths.append(resource.resource_path)
	_selected_resources_last_index = current_idx


func next_page() -> void:
	if _current_page < _page_count() - 1:
		_current_page += 1
		_emit_page_data()


func prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_emit_page_data()


func refresh_resource_list_values() -> void:
	if _current_class_name.is_empty():
		return
	_resolve_current_classes()
	_scan_current_properties()
	_scan_current_resources(true)
	_restore_selection()
	_current_page = 0
	_emit_page_data()


# ── Private ────────────────────────────────────────────────────────────────────

func _resolve_current_classes() -> void:
	if _include_subclasses:
		_current_included_class_names = ProjectClassScanner.get_descendant_classes(_current_class_name, global_class_to_parent_map)
	else:
		_current_included_class_names = [_current_class_name]
	current_class_script = _get_class_script(_current_class_name)


func _scan_current_properties() -> void:
	current_included_class_property_lists = ProjectClassScanner.get_properties_from_script_names(_current_included_class_names)

	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = current_included_class_property_lists.get(_current_class_name, empty_props)
	current_shared_propery_list = ProjectClassScanner.unite_classes_properties(_current_included_class_names, global_class_to_path_map)


func _restore_selection() -> void:
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in current_resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_selected_resources_last_index = current_resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())


func _rebuild_known_mtimes() -> void:
	_current_resource_mtimes.clear()
	for res: Resource in current_resources:
		_current_resource_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)


func _scan_current_resources(reseting: bool = false) -> void:
	if _current_class_name.is_empty():
		return

	if reseting:
		current_resources = ProjectClassScanner.load_classed_resources_from_dir(_current_included_class_names)
		_rebuild_known_mtimes()
		return

	var current_paths: Array[String] = ProjectClassScanner.scan_folder_for_classed_tres_paths(_current_included_class_names)
	var changed: bool = false
	var added_resources: Array[Resource] = []
	var modified_resources: Array[Resource] = []
	var removed_resources: Array[Resource] = []

	# Detect new and modified resources
	for path: String in current_paths:
		var mtime: int = FileAccess.get_modified_time(path)
		# Is a new resource
		if not _current_resource_mtimes.has(path):
			# New resource
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				current_resources.append(res)
				added_resources.append(res)
				changed = true
		# Is a changed resource
		elif mtime != _current_resource_mtimes[path]:
			# Modified resource — reload in place
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				for i: int in current_resources.size():
					if current_resources[i].resource_path == path:
						current_resources[i] = res
						break
				modified_resources.append(res)
				changed = true

	# Detect deleted resources
	var known_paths: Array = _current_resource_mtimes.keys()
	for path: String in known_paths:
		if not current_paths.has(path):
			for i: int in current_resources.size():
				if current_resources[i].resource_path == path:
					removed_resources.append(current_resources[i])
					current_resources.remove_at(i)
					break
			changed = true

	if not changed:
		return

	current_resources.sort_custom(func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_known_mtimes()
	_restore_selection()
	_emit_page_data_preserving_page()


	if not added_resources.is_empty():
		resources_added.emit(added_resources)
	if not removed_resources.is_empty():
		resources_removed.emit(removed_resources)
	if not modified_resources.is_empty():
		return


func _page_count() -> int:
	if current_resources.is_empty():
		return 1
	return ceili(float(current_resources.size()) / float(PAGE_SIZE))


func _emit_page_data() -> void:
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, current_resources.size())
	resources_replaced.emit(current_resources.slice(start, end), current_shared_propery_list)
	pagination_changed.emit(_current_page, _page_count())


func _emit_page_data_preserving_page() -> void:
	var max_page: int = _page_count() - 1
	if _current_page > max_page:
		_current_page = max_page
	_emit_page_data()


func _set_maps() -> void:
	global_class_map = ProjectClassScanner.build_global_classes_map()
	global_class_to_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_class_map)
	global_class_to_path_map = ProjectClassScanner.build_class_to_path_map(global_class_map)
	global_class_name_list = ProjectClassScanner.get_project_resource_classes(global_class_map)


func _on_script_classes_updated() -> void:
	print("classes updated")
	_classes_update_pending = true
	%RescanDebounceTimer.start_debouncing(_handle_global_classes_updated)


func _handle_global_classes_updated() -> void:
	_classes_update_pending = false

	var previous_classes: Array[String] = global_class_name_list.duplicate()
	_set_maps()

	# Class list unchanged — only check for property changes
	if previous_classes == global_class_name_list:
		_handle_property_changes()
		return

	# Class list changed
	_resave_orphaned_resources(previous_classes)
	project_classes_changed.emit(global_class_name_list)

	if _current_class_name.is_empty():
		return

	# Current Class is missing
	if not global_class_name_list.has(_current_class_name):
		var new_name: String = _detect_class_rename()
		# Current Class is deleted
		if new_name.is_empty():
			_clear_view()
			return
		# Current Class is renamed
		_current_class_name = new_name
		current_class_renamed.emit(new_name)
		refresh_resource_list_values()
		return

	if _has_current_class_set_changed(previous_classes):
		refresh_resource_list_values()
		return

	_handle_property_changes()


func _resave_orphaned_resources(previous_classes: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous_classes:
		if not global_class_name_list.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned_resources: Array[Resource] = (
		ProjectClassScanner.load_classed_resources_from_dir(removed_classes)
	)
	for res: Resource in orphaned_resources:
		ResourceSaver.save(res, res.resource_path)


func _detect_class_rename() -> String:
	if current_class_script == null:
		return ""
	var old_path: String = current_class_script.resource_path
	if old_path.is_empty():
		return ""
	for cls: String in global_class_to_path_map:
		if global_class_to_path_map[cls] == old_path:
			return cls
	return ""


func _handle_property_changes() -> void:
	if _current_class_name.is_empty():
		return
	var new_props: Array[ResourceProperty] = _get_current_class_props()
	if ResourceProperty.arrays_equal(new_props, current_class_property_list):
		return
	_scan_current_properties()
	for res: Resource in current_resources:
		ResourceSaver.save(res, res.resource_path)
	_restore_selection()
	_emit_page_data_preserving_page()


func _has_current_class_set_changed(previous_classes: Array[String]) -> bool:
	for cls: String in _current_included_class_names:
		if not previous_classes.has(cls) or not global_class_name_list.has(cls):
			return true
	return false


func _get_current_class_props() -> Array[ResourceProperty]:
	var script_path: String = global_class_to_path_map.get(_current_class_name, "")
	if not script_path.is_empty():
		return ProjectClassScanner.get_properties_from_script_path(script_path)
	var empty_props: Array[ResourceProperty] = []
	return empty_props


func _get_class_script(class_name_str: String) -> GDScript:
	var script_path: String = global_class_to_path_map.get(class_name_str, "")
	if not script_path.is_empty():
		return load(script_path)
	return null


func _clear_view() -> void:
	_current_class_name = ""
	_current_included_class_names.clear()
	current_class_script = null
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = empty_props
	current_included_class_property_lists.clear()
	current_shared_propery_list.clear()
	current_resources.clear()
	selected_resources.clear()
	_selected_paths.clear()
	_selected_resources_last_index = -1
	_current_page = 0
	var empty_resources: Array[Resource] = []
	var empty_current_shared_propery_list: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_current_shared_propery_list)
	selection_changed.emit(empty_resources)
	pagination_changed.emit(0, 1)


func _on_filesystem_changed() -> void:
	print("fs changed ")
	if _classes_update_pending:
		return
	%RescanDebounceTimer.start_debouncing(_scan_current_resources)
