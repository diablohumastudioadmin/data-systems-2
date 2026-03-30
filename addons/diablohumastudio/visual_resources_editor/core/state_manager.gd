@tool
class_name VREStateManager
extends RefCounted

signal resources_replaced(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)
signal resources_edited(resources: Array[Resource])

const PAGE_SIZE: int = 50

var classes_repo: IClassesRepository
var resources_repo: IResourcesRepository

var _include_subclasses: bool = true

var _current_class_name: String = ""
var _current_included_class_names: Array[String] = []

var selected_resources: Array[Resource] = []
var _selected_paths: Array[String] = []
var _selected_resources_last_index: int = -1

var _current_page: int = 0
var _current_page_resources: Array[Resource] = []


func _init(
		p_classes_repo: IClassesRepository,
		p_resources_repo: IResourcesRepository) -> void:

	classes_repo = p_classes_repo
	resources_repo = p_resources_repo

	classes_repo.class_list_changed.connect(_on_class_list_changed)
	classes_repo.current_property_list_changed.connect(_on_property_list_changed)
	classes_repo.orphaned_resources_found.connect(_on_orphaned_resources_found)

	resources_repo.resources_reset.connect(_on_resources_reset)
	resources_repo.resources_changed.connect(_on_resources_changed)


func shutdown() -> void:
	classes_repo = null
	resources_repo = null


# ── Public API ────────────────────────────────────────────────────────────────

func set_current_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	refresh_resource_list_values()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	refresh_resource_list_values()


func notify_resources_edited(resources: Array[Resource]) -> void:
	resources_edited.emit(resources)


func refresh_resource_list_values() -> void:
	if _current_class_name.is_empty():
		return
	_current_included_class_names = classes_repo.resolve_included_classes(
		_current_class_name, _include_subclasses)
	classes_repo.scan_properties(_current_class_name, _current_included_class_names)
	resources_repo.load_resources(_current_included_class_names)
	# resources_repo emits resources_reset → _on_resources_reset handles page + UI


# ── Selection ─────────────────────────────────────────────────────────────────

func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	var current_idx: int = resources_repo.resources.find(resource)
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
		var res: Resource = resources_repo.resources[from + i]
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


# ── Pagination ────────────────────────────────────────────────────────────────

func next_page() -> void:
	if _current_page < _page_count() - 1:
		_set_current_page(_current_page + 1)


func prev_page() -> void:
	if _current_page > 0:
		_set_current_page(_current_page - 1)


func _set_current_page(page: int) -> void:
	_current_page = clampi(page, 0, _page_count() - 1)
	_slice_page()
	_emit_page_data()


func _page_count() -> int:
	if resources_repo.resources.is_empty():
		return 1
	return ceili(float(resources_repo.resources.size()) / float(PAGE_SIZE))


func _slice_page() -> void:
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, resources_repo.resources.size())
	_current_page_resources = resources_repo.resources.slice(start, end)


func _emit_page_data() -> void:
	resources_replaced.emit(_current_page_resources, classes_repo.shared_property_list)
	pagination_changed.emit(_current_page, _page_count())


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

	# Class list changed but current set is the same
	# Property changes are handled by the repo's _check_property_changes → _on_property_list_changed


func _on_property_list_changed() -> void:
	if _current_class_name.is_empty():
		return
	for res: Resource in resources_repo.resources:
		ResourceSaver.save(res, res.resource_path)
	_restore_selection()
	_set_current_page(_current_page)


func _on_orphaned_resources_found(orphaned: Array[Resource]) -> void:
	for res: Resource in orphaned:
		ResourceSaver.save(res, res.resource_path)


# ── ResourcesRepository signal handlers ───────────────────────────────────────

func _on_resources_reset(_resources: Array[Resource]) -> void:
	_current_page = 0
	_restore_selection()
	_slice_page()
	_emit_page_data()


func _on_resources_changed(
		added: Array[Resource], removed: Array[Resource], modified: Array[Resource]) -> void:
	_restore_selection()
	_slice_page()

	var page_added: Array[Resource] = _page_filter(added)
	var page_removed: Array[Resource] = _page_filter(removed)
	var page_modified: Array[Resource] = _page_filter(modified)

	if not page_removed.is_empty():
		resources_removed.emit(page_removed)
	if not page_added.is_empty():
		resources_added.emit(page_added)
	if not page_modified.is_empty():
		resources_modified.emit(page_modified)
	pagination_changed.emit(_current_page, _page_count())


func _page_filter(res_list: Array[Resource]) -> Array[Resource]:
	var page_paths: Dictionary[String, bool] = {}
	for res: Resource in _current_page_resources:
		page_paths[res.resource_path] = true
	var filtered: Array[Resource] = []
	for res: Resource in res_list:
		if page_paths.has(res.resource_path):
			filtered.append(res)
	return filtered


# ── Private helpers ───────────────────────────────────────────────────────────

func _restore_selection() -> void:
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in resources_repo.resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_selected_resources_last_index = resources_repo.resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())


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
	selected_resources.clear()
	_selected_paths.clear()
	_selected_resources_last_index = -1
	_current_page = 0
	_current_page_resources.clear()
	var empty_resources: Array[Resource] = []
	var empty_props: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_props)
	selection_changed.emit(empty_resources)
	pagination_changed.emit(0, 1)
