@tool
class_name VREModel
extends RefCounted

# ── Signals (public API) ──────────────────────────────────────────
signal resources_replaced(resources: Array[Resource], current_shared_property_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
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


func request_create_new_resouce() -> void:
	create_new_resource_requested.emit()


func report_error(message: String) -> void:
	error_occurred.emit(message)


func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	_selection.set_selected(resource, ctrl_held, shift_held, resource_repo.current_class_resources)


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
	current_included_class_property_lists = ProjectClassScanner.get_properties_from_script_names(
		_current_included_class_names, class_registry.global_class_to_path_map)
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = current_included_class_property_lists.get(
		session.selected_class, empty_props)
	current_shared_property_list = ProjectClassScanner.unite_classes_properties(
		_current_included_class_names, class_registry.global_class_to_path_map)


# ── Manager signal handlers ──────────────────────────────────────────────────

func _on_selection_manager_changed(resources: Array[Resource]) -> void:
	session.selected_resources = resources
	selection_changed.emit(resources)


func _on_pagination_manager_changed(page: int, page_count: int) -> void:
	session.current_page = page
	pagination_changed.emit(page, page_count)


func _on_resources_reset(_resources: Array[Resource]) -> void:
	_apply_sort()
	_selection.restore(resource_repo.current_class_resources)
	_pagination.reset(resource_repo.current_class_resources)


func _on_resources_delta(
	added: Array[Resource], removed: Array[Resource], modified: Array[Resource]
) -> void:
	_apply_sort()
	_selection.restore(resource_repo.current_class_resources)
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
	_resave_orphaned_resources(previous, current)
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

	_handle_property_changes()


# ── Filesystem / script class event handlers ──────────────────────────────────

func _on_script_classes_updated() -> void:
	_handle_script_classes_updated()


func _handle_script_classes_updated() -> void:
	var list_changed: bool = class_registry.rebuild()
	if not list_changed:
		_handle_property_changes()


func _on_filesystem_changed() -> void:
	_refresh_current_class_resources()


func _refresh_current_class_resources() -> void:
	if session.selected_class.is_empty():
		return
	resource_repo.scan_for_changes(_current_included_class_names)


# ── Internal state helpers ────────────────────────────────────────────────────

func _resave_orphaned_resources(previous: Array[String], current: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous:
		if not current.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned: Array[Resource] = ProjectClassScanner.load_classed_resources_from_dir(removed_classes)
	resource_repo.resave_resources(orphaned)


func _handle_property_changes() -> void:
	if session.selected_class.is_empty():
		return
	var new_props: Array[ResourceProperty] = class_registry.get_properties(session.selected_class)
	if ResourceProperty.arrays_equal(new_props, current_class_property_list):
		return
	_scan_current_properties()
	_validate_sort_column()
	resource_repo.resave_all()
	_apply_sort()
	_selection.restore(resource_repo.current_class_resources)
	_pagination.refresh_silent(resource_repo.current_class_resources)
	resources_replaced.emit(_pagination.current_page_resources, current_shared_property_list)
	pagination_changed.emit(
		_pagination.current_page(),
		_pagination.page_count(resource_repo.current_class_resources.size())
	)


func _apply_sort() -> void:
	_sort_resources(
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


static func _sort_resources(
	resources: Array[Resource],
	column: String,
	ascending: bool,
	props: Array[ResourceProperty]
) -> void:
	if resources.size() < 2:
		return

	var prop_type: int = TYPE_NIL
	if not column.is_empty():
		for p: ResourceProperty in props:
			if p.name == column:
				prop_type = p.type
				break

	resources.sort_custom(func(a: Resource, b: Resource) -> bool:
		var val_a: Variant = _sort_value(a, column, prop_type)
		var val_b: Variant = _sort_value(b, column, prop_type)

		# null sorts last regardless of direction
		if val_a == null and val_b == null:
			return a.resource_path < b.resource_path
		if val_a == null:
			return false
		if val_b == null:
			return true

		var cmp: int = _compare_values(val_a, val_b, prop_type)
		if cmp == 0:
			return a.resource_path < b.resource_path
		return cmp < 0 if ascending else cmp > 0
	)


static func _sort_value(res: Resource, column: String, prop_type: int) -> Variant:
	if column.is_empty():
		return res.resource_path.get_file()
	var val: Variant = res.get(column) if column in res else null
	return val


static func _compare_values(a: Variant, b: Variant, prop_type: int) -> int:
	match prop_type:
		TYPE_STRING, TYPE_STRING_NAME:
			return str(a).naturalnocasecmp_to(str(b))
		TYPE_INT, TYPE_FLOAT:
			var fa: float = float(a)
			var fb: float = float(b)
			if fa < fb: return -1
			if fa > fb: return 1
			return 0
		TYPE_BOOL:
			var ia: int = 1 if a else 0
			var ib: int = 1 if b else 0
			if ia < ib: return -1
			if ia > ib: return 1
			return 0
		TYPE_VECTOR2:
			var la: float = a.length()
			var lb: float = b.length()
			if la < lb: return -1
			if la > lb: return 1
			return 0
		TYPE_VECTOR3:
			var la: float = a.length()
			var lb: float = b.length()
			if la < lb: return -1
			if la > lb: return 1
			return 0
		TYPE_COLOR:
			if a.h != b.h:
				return -1 if a.h < b.h else 1
			if a.v != b.v:
				return -1 if a.v < b.v else 1
			return 0
		TYPE_OBJECT:
			var pa: String = a.resource_path.get_file() if a is Resource and a.resource_path else ""
			var pb: String = b.resource_path.get_file() if b is Resource and b.resource_path else ""
			return pa.naturalnocasecmp_to(pb)
		TYPE_NIL:
			# File-name column (column == "")
			return str(a).naturalnocasecmp_to(str(b))
		_:
			return str(a).naturalnocasecmp_to(str(b))


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
