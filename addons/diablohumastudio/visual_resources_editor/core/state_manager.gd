@tool
class_name VREStateManager
extends Node

# ── Signals (public API — unchanged) ──────────────────────────────────────────
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

# ── Sub-managers ───────────────────────────────────────────────────────────────
var _class_registry: ClassRegistry
var _resource_repo: ResourceRepository
var _selection: SelectionManager
var _pagination: PaginationManager
var _fs_listener: EditorFileSystemListener

# ── Coordinator-only state ────────────────────────────────────────────────────
var _current_class_name: String = ""
var _include_subclasses: bool = true
var _current_included_class_names: Array[String] = []
# Properties read by BulkEditor — owned here because they span ClassRegistry
# data and the current UI selection context.
var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var current_included_class_property_lists: Dictionary = {}
var current_shared_property_list: Array[ResourceProperty] = []

# ── Public read-only accessors (same API as before) ───────────────────────────
var current_class_name: String:
	get: return _current_class_name

var selected_resources: Array[Resource]:
	get: return _selection.selected_resources

var _selected_paths: Array[String]:
	get: return _selection.get_paths()

var global_class_map: Array[Dictionary]:
	get: return _class_registry.global_class_map

var global_class_name_list: Array[String]:
	get: return _class_registry.global_class_name_list

var global_class_to_path_map: Dictionary[String, String]:
	get: return _class_registry.global_class_to_path_map

var current_class_resources: Array[Resource]:
	get: return _resource_repo.current_class_resources


func _ready() -> void:
	if not Engine.is_editor_hint(): return

	_class_registry = ClassRegistry.new()
	_resource_repo = ResourceRepository.new()
	_selection = SelectionManager.new()
	_pagination = PaginationManager.new()
	_fs_listener = EditorFileSystemListener.new()

	_class_registry.classes_changed.connect(_on_classes_changed)
	_resource_repo.resources_reset.connect(_on_resources_reset)
	_resource_repo.resources_delta.connect(_on_resources_delta)
	_selection.selection_changed.connect(selection_changed.emit)
	_pagination.page_replaced.connect(_on_page_replaced)
	_pagination.page_delta.connect(_on_page_delta)
	_pagination.pagination_changed.connect(pagination_changed.emit)
	_fs_listener.filesystem_changed.connect(_on_filesystem_changed)
	_fs_listener.script_classes_updated.connect(_on_script_classes_updated)

	_fs_listener.start()
	_class_registry.rebuild()
	project_classes_changed.emit(_class_registry.global_class_name_list)


func _exit_tree() -> void:
	if not Engine.is_editor_hint(): return
	_fs_listener.stop()


# ── Public API (unchanged) ─────────────────────────────────────────────────────

func set_current_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	refresh_resource_list_values()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	refresh_resource_list_values()


func notify_resources_edited(resources: Array[Resource]) -> void:
	resources_edited.emit(resources)


func request_delete_selected_resources(resource_paths: Array[String]) -> void:
	delete_selected_requested.emit(resource_paths)


func request_create_new_resouce() -> void:
	create_new_resource_requested.emit()


func report_error(message: String) -> void:
	error_occurred.emit(message)


func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	_selection.set_selected(resource, ctrl_held, shift_held, _resource_repo.current_class_resources)


func next_page() -> void:
	_pagination.next(_resource_repo.current_class_resources)


func prev_page() -> void:
	_pagination.prev(_resource_repo.current_class_resources)


func refresh_resource_list_values() -> void:
	if _current_class_name.is_empty():
		return
	_resolve_current_classes()
	_scan_current_properties()
	_resource_repo.load_resources(_current_included_class_names)
	# resources_reset fires → _on_resources_reset → selection.restore + pagination.reset


# ── Private coordinator logic ──────────────────────────────────────────────────

func _resolve_current_classes() -> void:
	_current_included_class_names = _class_registry.get_included_classes(
		_current_class_name, _include_subclasses)
	current_class_script = _class_registry.get_class_script(_current_class_name)


func _scan_current_properties() -> void:
	current_included_class_property_lists = ProjectClassScanner.get_properties_from_script_names(
		_current_included_class_names, _class_registry.global_class_to_path_map)
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = current_included_class_property_lists.get(
		_current_class_name, empty_props)
	current_shared_property_list = ProjectClassScanner.unite_classes_properties(
		_current_included_class_names, _class_registry.global_class_to_path_map)


# ── ResourceRepository signal handlers ────────────────────────────────────────

func _on_resources_reset(resources: Array[Resource]) -> void:
	_selection.restore(resources)
	_pagination.reset(resources)
	# pagination.reset emits page_replaced → _on_page_replaced → resources_replaced


func _on_resources_delta(
	added: Array[Resource], removed: Array[Resource], modified: Array[Resource]
) -> void:
	_selection.restore(_resource_repo.current_class_resources)
	# Re-slice the current page; pagination emits page_delta → _on_page_delta → granular signals
	_pagination.set_page(_pagination.current_page(), _resource_repo.current_class_resources)


# ── PaginationManager signal handlers ─────────────────────────────────────────

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

	if _current_class_name.is_empty():
		return

	if not current.has(_current_class_name):
		var old_path: String = current_class_script.resource_path if current_class_script else ""
		var new_name: String = _class_registry.detect_rename(old_path)
		if new_name.is_empty():
			_clear_view()
		else:
			_current_class_name = new_name
			current_class_renamed.emit(new_name)
			refresh_resource_list_values()
		return

	if _class_registry.has_class_set_changed(previous, _current_included_class_names):
		refresh_resource_list_values()
		return

	_handle_property_changes()


# ── Filesystem / script class event handlers ───────────────────────────────────

func _on_script_classes_updated() -> void:
	%RescanDebounceTimer.start_debouncing(_handle_script_classes_updated)


func _handle_script_classes_updated() -> void:
	var list_changed: bool = _class_registry.rebuild()
	if not list_changed:
		# Class list unchanged — check for property schema changes only.
		# If list changed, _on_classes_changed fires automatically via ClassRegistry signal.
		_handle_property_changes()


func _on_filesystem_changed() -> void:
	%RescanDebounceTimer.start_debouncing(_refresh_current_class_resources)


func _refresh_current_class_resources() -> void:
	if _current_class_name.is_empty():
		return
	_resource_repo.scan_for_changes(_current_included_class_names)
	# resources_delta fires → _on_resources_delta


# ── Internal state helpers ─────────────────────────────────────────────────────

func _resave_orphaned_resources(previous: Array[String], current: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous:
		if not current.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned: Array[Resource] = ProjectClassScanner.load_classed_resources_from_dir(removed_classes)
	_resource_repo.resave_resources(orphaned)


func _handle_property_changes() -> void:
	if _current_class_name.is_empty():
		return
	var new_props: Array[ResourceProperty] = _class_registry.get_properties(_current_class_name)
	if ResourceProperty.arrays_equal(new_props, current_class_property_list):
		return
	_scan_current_properties()
	_resource_repo.resave_all()
	_selection.restore(_resource_repo.current_class_resources)
	# Re-slice silently — schema changed, emit full resources_replaced (not a delta).
	_pagination.refresh_silent(_resource_repo.current_class_resources)
	resources_replaced.emit(_pagination.current_page_resources, current_shared_property_list)
	pagination_changed.emit(
		_pagination.current_page(),
		_pagination.page_count(_resource_repo.current_class_resources.size())
	)


func _clear_view() -> void:
	_current_class_name = ""
	_current_included_class_names.clear()
	current_class_script = null
	current_class_property_list = []
	current_included_class_property_lists.clear()
	current_shared_property_list.clear()
	_resource_repo.clear()
	_selection.clear()
	var empty_resources: Array[Resource] = []
	var empty_props: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_props)
	pagination_changed.emit(0, 1)
