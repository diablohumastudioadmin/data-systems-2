@tool
class_name VREModel
extends RefCounted

# ── Signals (public API) ──────────────────────────────────────────
signal resources_replaced(resources: Array[Resource], current_shared_property_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(paths: Array[String])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)
signal resources_edited(resources: Array[Resource])
signal error_occurred(message: String)
signal delete_selected_requested(selected_resources_paths: Array[String])
signal create_new_resource_requested()

# ── Sub-managers and Models ────────────────────────────────────────────────────────
var session: SessionStateModel
var class_registry: ClassRegistry
var resource_repo: ResourceRepository
var _selection: SelectionManager
var _pagination: PaginationManager
var _fs_listener: EditorFileSystemListener

# ── Coordinator-only state ────────────────────────────────────────────────────
var _current_included_class_names: Array[String] = []

# Properties read by BulkEditor
var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var current_included_class_property_lists: Dictionary = {}
var current_shared_property_list: Array[ResourceProperty] = []

# ── Public read-only accessors ────────────────────────────────────────────────
var global_class_map: Array[Dictionary]:
	get: return class_registry.global_class_map

var global_class_name_list: Array[String]:
	get: return class_registry.global_class_name_list

var global_class_to_path_map: Dictionary[String, String]:
	get: return class_registry.global_class_to_path_map

var current_class_resources: Array[Resource]:
	get: return resource_repo.current_class_resources


func _init() -> void:
	session = SessionStateModel.new()
	class_registry = ClassRegistry.new()
	resource_repo = ResourceRepository.new()
	_selection = SelectionManager.new()
	_pagination = PaginationManager.new()
	_fs_listener = EditorFileSystemListener.new()


func start() -> void:
	if not Engine.is_editor_hint(): return

	class_registry.classes_changed.connect(_on_classes_changed)
	resource_repo.resources_reset.connect(_on_resources_reset)
	resource_repo.resources_delta.connect(_on_resources_delta)
	
	_selection.selection_changed.connect(_on_selection_manager_changed)
	
	_pagination.page_replaced.connect(_on_page_replaced)
	_pagination.page_delta.connect(_on_page_delta)
	_pagination.pagination_changed.connect(_on_pagination_manager_changed)
	
	_fs_listener.filesystem_changed.connect(_on_filesystem_changed)
	_fs_listener.script_classes_updated.connect(_on_script_classes_updated)
	
	# Wire SessionStateModel coordination
	session.selected_class_changed.connect(_on_session_selected_class_changed)
	session.include_subclasses_changed.connect(_on_session_include_subclasses_changed)
	session.sort_changed.connect(_on_session_sort_changed)

	_fs_listener.start()
	class_registry.rebuild()
	project_classes_changed.emit(class_registry.global_class_name_list)


func stop() -> void:
	if not Engine.is_editor_hint(): return
	_fs_listener.stop()


# ── Public API ───────────────────────────────────────────────────────────────

func notify_resources_edited(resources: Array[Resource]) -> void:
	resources_edited.emit(resources)


func request_delete_selected_resources(resource_paths: Array[String]) -> void:
	delete_selected_requested.emit(resource_paths)


func request_create_new_resource() -> void:
	create_new_resource_requested.emit()


func report_error(message: String) -> void:
	error_occurred.emit(message)


func set_selected_by_path(path: String, ctrl_held: bool, shift_held: bool) -> void:
	var all_paths: Array[String] = []
	for res: Resource in resource_repo.current_class_resources:
		all_paths.append(res.resource_path)
	_selection.set_selected(path, ctrl_held, shift_held, all_paths)


func next_page() -> void:
	_pagination.next(resource_repo.current_class_resources)


func prev_page() -> void:
	_pagination.prev(resource_repo.current_class_resources)


func refresh_resource_list_values() -> void:
	if session.selected_class.is_empty():
		return
	_resolve_current_classes()
	_scan_current_properties()
	_validate_sort_column()
	resource_repo.load_resources(_current_included_class_names)


# ── Session State Handlers ───────────────────────────────────────────────────

func _on_session_selected_class_changed(_class_name: String) -> void:
	refresh_resource_list_values()


func _on_session_include_subclasses_changed(_include: bool) -> void:
	refresh_resource_list_values()


func _on_session_sort_changed(_column: String, _ascending: bool) -> void:
	_apply_sort()
	_pagination.reset(resource_repo.current_class_resources)


# ── Private coordinator logic ────────────────────────────────────────────────

func _resolve_current_classes() -> void:
	_current_included_class_names = class_registry.get_included_classes(
		session.selected_class, session.include_subclasses)
	current_class_script = class_registry.get_class_script(session.selected_class)


func _scan_current_properties() -> void:
	current_included_class_property_lists = class_registry.get_properties_for(
		_current_included_class_names)
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = current_included_class_property_lists.get(
		session.selected_class, empty_props)
	current_shared_property_list = class_registry.get_shared_properties(
		_current_included_class_names)
	resource_repo.update_last_known_props(current_class_property_list)


# ── Manager signal handlers ──────────────────────────────────────────────────

func _on_selection_manager_changed(paths: Array[String]) -> void:
	session.selected_paths = paths
	selection_changed.emit(paths)


func _on_pagination_manager_changed(page: int, page_count: int) -> void:
	session.current_page = page
	pagination_changed.emit(page, page_count)


func _on_resources_reset(_resources: Array[Resource]) -> void:
	_apply_sort()
	_pagination.reset(resource_repo.current_class_resources)


func _on_resources_delta(
	added: Array[Resource], removed: Array[Resource], modified: Array[Resource]
) -> void:
	_apply_sort()
	_pagination.set_page(_pagination.current_page(), resource_repo.current_class_resources)


func _on_page_replaced(resources: Array[Resource]) -> void:
	resources_replaced.emit(resources, current_shared_property_list)


func _on_page_delta(
	added: Array[Resource], removed: Array[Resource], modified: Array[Resource]
) -> void:
	if not removed.is_empty(): resources_removed.emit(removed)
	if not added.is_empty(): resources_added.emit(added)
	if not modified.is_empty(): resources_modified.emit(modified)


# ── ClassRegistry signal handlers ─────────────────────────────────────────────

func _on_classes_changed(previous: Array[String], current: Array[String]) -> void:
	var schema_resaved: bool = resource_repo.on_classes_changed(
		previous, current, session.selected_class, class_registry)
	project_classes_changed.emit(current)

	if session.selected_class.is_empty():
		return

	if not current.has(session.selected_class):
		var old_path: String = current_class_script.resource_path if current_class_script else ""
		var new_name: String = class_registry.detect_rename(old_path)
		if new_name.is_empty():
			_clear_view()
		else:
			session.selected_class = new_name
			current_class_renamed.emit(new_name)
			refresh_resource_list_values()
		return

	if class_registry.has_class_set_changed(previous, _current_included_class_names):
		refresh_resource_list_values()
		return

	if schema_resaved:
		_refresh_property_ui()


# ── Filesystem / script class event handlers ──────────────────────────────────

func _on_script_classes_updated() -> void:
	_handle_script_classes_updated()


func _handle_script_classes_updated() -> void:
	var list_changed: bool = class_registry.rebuild()
	if list_changed:
		return
	# No class add/remove, but an existing class may have had its props edited.
	# Same-list args make on_classes_changed skip the orphan path and run only
	# the schema-diff resave for the selected class.
	var current_classes: Array[String] = class_registry.global_class_name_list
	var schema_resaved: bool = resource_repo.on_classes_changed(
		current_classes, current_classes, session.selected_class, class_registry)
	if schema_resaved:
		_refresh_property_ui()


func _on_filesystem_changed() -> void:
	_refresh_current_class_resources()


func _refresh_current_class_resources() -> void:
	if session.selected_class.is_empty():
		return
	resource_repo.scan_for_changes(_current_included_class_names)


# ── Internal state helpers ────────────────────────────────────────────────────

## UI-side response to a schema change. Disk resave has already been done
## by ResourceRepository.on_classes_changed.
func _refresh_property_ui() -> void:
	if session.selected_class.is_empty():
		return
	_scan_current_properties()
	_validate_sort_column()
	_apply_sort()
	_pagination.refresh_silent(resource_repo.current_class_resources)
	resources_replaced.emit(_pagination.current_page_resources, current_shared_property_list)
	pagination_changed.emit(
		_pagination.current_page(),
		_pagination.page_count(resource_repo.current_class_resources.size())
	)


func _apply_sort() -> void:
	ResourceSorter.sort(
		resource_repo.current_class_resources,
		session.sort_column,
		session.sort_ascending,
		current_shared_property_list)


func _validate_sort_column() -> void:
	if session.sort_column.is_empty():
		return
	for prop: ResourceProperty in current_shared_property_list:
		if prop.name == session.sort_column:
			return
	session.set_sort("", true)


func _clear_view() -> void:
	session.selected_class = ""
	_current_included_class_names.clear()
	current_class_script = null
	current_class_property_list = []
	current_included_class_property_lists.clear()
	current_shared_property_list.clear()
	resource_repo.clear()
	_selection.clear()
	var empty_resources: Array[Resource] = []
	var empty_props: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_props)
	pagination_changed.emit(0, 1)
