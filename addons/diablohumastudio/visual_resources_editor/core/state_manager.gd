@tool
class_name VREStateManager
extends Node

signal resources_replaced(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)

const PAGE_SIZE: int = 50

var classes_repo: IClassesRepository

var _include_subclasses: bool = true

var _current_class_name: String = ""
var _current_included_class_names: Array[String] = []

var current_class_resources: Array[Resource] = []
var _current_class_resources_mtimes: Dictionary[String, int] = {}

var selected_resources: Array[Resource] = []
var _selected_paths: Array[String] = []
var _selected_resources_last_index: int = -1

var _current_page: int = 0
var _current_page_resources: Array[Resource] = []
var current_page_resources_mtimes: Dictionary[String, int] = {}

var _classes_update_pending: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint(): return

	if classes_repo == null:
		classes_repo = EditorClassesRepository.new()
	classes_repo.class_list_changed.connect(_on_class_list_changed)
	classes_repo._property_list_changed.connect(_on_property_list_changed)
	classes_repo.orphaned_resources_found.connect(_on_orphaned_resources_found)

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
	var current_idx: int = current_class_resources.find(resource)
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
		var res: Resource = current_class_resources[from + i]
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
		_set_current_page(_current_page + 1)


func prev_page() -> void:
	if _current_page > 0:
		_set_current_page(_current_page - 1)


func refresh_resource_list_values() -> void:
	if _current_class_name.is_empty():
		return
	_current_included_class_names = classes_repo.resolve_included_classes(
		_current_class_name, _include_subclasses)
	classes_repo.scan_properties(_current_class_name, _current_included_class_names)
	set_current_class_resources(true)
	_set_current_page(0, true)
	_emit_page_data()


# ── Private ────────────────────────────────────────────────────────────────────

func _restore_selection() -> void:
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in current_class_resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_selected_resources_last_index = current_class_resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())


func _rebuild_current_class_resource_mtimes() -> void:
	_current_class_resources_mtimes.clear()
	for res: Resource in current_class_resources:
		_current_class_resources_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)


func _rebuild_current_page_resource_mtimes() -> void:
	current_page_resources_mtimes.clear()
	for res: Resource in _current_page_resources:
		current_page_resources_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)


func set_current_class_resources(reseting: bool = false) -> void:
	if _current_class_name.is_empty():
		return

	if reseting:
		current_class_resources = ProjectScanner.load_classed_resources_from_dir(_current_included_class_names)
	else:
		current_class_resources = _scan_class_resources_for_changes()

	current_class_resources.sort_custom(func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_current_class_resource_mtimes()
	_restore_selection()


func _scan_class_resources_for_changes() -> Array[Resource]:
	var updated_class_resources: Array[Resource] = current_class_resources.duplicate()
	var current_paths: Array[String] = ProjectScanner.scan_folder_for_classed_tres_paths(_current_included_class_names)
	var changed: bool = false

	# Detect new and modified resources
	for path: String in current_paths:
		var mtime: int = FileAccess.get_modified_time(path)
		if not _current_class_resources_mtimes.has(path):
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				updated_class_resources.append(res)
				changed = true
		elif mtime != _current_class_resources_mtimes[path]:
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				for i: int in updated_class_resources.size():
					if updated_class_resources[i].resource_path == path:
						updated_class_resources[i] = res
						break
				changed = true

	# Detect deleted resources
	var known_paths: Array = _current_class_resources_mtimes.keys()
	for path: String in known_paths:
		if not current_paths.has(path):
			for i: int in updated_class_resources.size():
				if updated_class_resources[i].resource_path == path:
					updated_class_resources.remove_at(i)
					break
			changed = true

	if not changed:
		return current_class_resources
	return updated_class_resources


func _set_current_page(page: int, reseting: bool = false) -> void:
	var max_page: int = _page_count() - 1
	_current_page = clampi(page, 0, max_page)
	set_current_page_resources(reseting)
	if not reseting:
		pagination_changed.emit(_current_page, _page_count())


func set_current_page_resources(reseting: bool = false) -> void:
	var previous_page_resources: Array[Resource] = _current_page_resources.duplicate()
	var previous_page_resources_mtimes: Dictionary[String, int] = current_page_resources_mtimes.duplicate()
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, current_class_resources.size())
	_current_page_resources = current_class_resources.slice(start, end)
	_rebuild_current_page_resource_mtimes()
	if reseting:
		return
	_scan_page_resources_for_changes(previous_page_resources, previous_page_resources_mtimes)


func _scan_page_resources_for_changes(
		previous_page_resources: Array[Resource],
		previous_page_resources_mtimes: Dictionary[String, int]) -> void:
	var previous_page_resources_map: Dictionary[String, Resource] = {}
	for res: Resource in previous_page_resources:
		previous_page_resources_map[res.resource_path] = res

	var current_page_resources_map: Dictionary[String, Resource] = {}
	for res: Resource in _current_page_resources:
		current_page_resources_map[res.resource_path] = res

	var removed_resources: Array[Resource] = []
	for path: String in previous_page_resources_map:
		if not current_page_resources_map.has(path):
			removed_resources.append(previous_page_resources_map[path])

	var added_resources: Array[Resource] = []
	for path: String in current_page_resources_map:
		if not previous_page_resources_map.has(path):
			added_resources.append(current_page_resources_map[path])

	var modified_resources: Array[Resource] = []
	for path: String in current_page_resources_map:
		if not previous_page_resources_map.has(path):
			continue
		if previous_page_resources_mtimes.get(path, -1) != current_page_resources_mtimes.get(path, -1):
			modified_resources.append(current_page_resources_map[path])

	if not removed_resources.is_empty():
		resources_removed.emit(removed_resources)
	if not added_resources.is_empty():
		resources_added.emit(added_resources)
	if not modified_resources.is_empty():
		resources_modified.emit(modified_resources)


func _page_count() -> int:
	if current_class_resources.is_empty():
		return 1
	return ceili(float(current_class_resources.size()) / float(PAGE_SIZE))


func _emit_page_data() -> void:
	resources_replaced.emit(_current_page_resources, classes_repo.shared_property_list)
	pagination_changed.emit(_current_page, _page_count())


func _emit_page_data_preserving_page() -> void:
	_set_current_page(_current_page, true)
	_emit_page_data()


# ── EditorFileSystem signal handlers ──────────────────────────────────────────

func _on_script_classes_updated() -> void:
	_classes_update_pending = true
	classes_repo.rebuild()


func _on_filesystem_changed() -> void:
	if _classes_update_pending:
		_classes_update_pending = false
		return
	_refresh_current_class_resources()


func _refresh_current_class_resources() -> void:
	if _current_class_name.is_empty():
		return
	set_current_class_resources(false)
	_set_current_page(_current_page)


# ── ClassesRepository signal handlers ─────────────────────────────────────────

func _on_class_list_changed(classes: Array[String]) -> void:
	project_classes_changed.emit(classes)

	if _current_class_name.is_empty():
		return

	# Current class is missing
	if not classes.has(_current_class_name):
		var new_name: String = _detect_class_rename()
		# Current class is deleted
		if new_name.is_empty():
			_clear_view()
			return
		# Current class is renamed
		_current_class_name = new_name
		current_class_renamed.emit(new_name)
		refresh_resource_list_values()
		return

	# Check if any class in current included set was added or removed
	if _has_current_class_set_changed():
		refresh_resource_list_values()
		return

	# Class list changed but current set is the same — check property changes
	_check_and_apply_property_changes()


func _on_property_list_changed() -> void:
	_check_and_apply_property_changes()


func _on_orphaned_resources_found(orphaned: Array[Resource]) -> void:
	for res: Resource in orphaned:
		ResourceSaver.save(res, res.resource_path)


# ── Private helpers ───────────────────────────────────────────────────────────

func _check_and_apply_property_changes() -> void:
	if _current_class_name.is_empty():
		return
	var old_props: Array[ResourceProperty] = classes_repo.current_class_property_list.duplicate()
	classes_repo.scan_properties(_current_class_name, _current_included_class_names)
	if ResourceProperty.arrays_equal(old_props, classes_repo.current_class_property_list):
		return
	for res: Resource in current_class_resources:
		ResourceSaver.save(res, res.resource_path)
	_restore_selection()
	_emit_page_data_preserving_page()


func _has_current_class_set_changed() -> bool:
	var new_included: Array[String] = classes_repo.resolve_included_classes(
		_current_class_name, _include_subclasses)
	if new_included.size() != _current_included_class_names.size():
		return true
	for cls: String in _current_included_class_names:
		if not new_included.has(cls):
			return true
	return false


func _detect_class_rename() -> String:
	if classes_repo.current_class_script == null:
		return ""
	var old_path: String = classes_repo.current_class_script.resource_path
	if old_path.is_empty():
		return ""
	for cls: String in classes_repo.class_to_path_map:
		if classes_repo.class_to_path_map[cls] == old_path:
			return cls
	return ""


func _clear_view() -> void:
	_current_class_name = ""
	_current_included_class_names.clear()
	current_class_resources.clear()
	_current_class_resources_mtimes.clear()
	selected_resources.clear()
	_selected_paths.clear()
	_selected_resources_last_index = -1
	_current_page = 0
	_current_page_resources.clear()
	current_page_resources_mtimes.clear()
	var empty_resources: Array[Resource] = []
	var empty_props: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_props)
	selection_changed.emit(empty_resources)
	pagination_changed.emit(0, 1)
