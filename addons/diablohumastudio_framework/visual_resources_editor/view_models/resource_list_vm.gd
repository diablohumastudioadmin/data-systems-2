@tool
class_name ResourceListVM
extends RefCounted

signal rows_replaced(rows: Array[ResourceRowVM])
signal rows_edited(resources: Array[Resource])
signal columns_changed(columns: Array[ResourceProperty])
signal sort_state_changed(column: String, ascending: bool)
signal pagination_state_changed(page: int, total_pages: int)
signal status_text_changed(visible_count: int, selected_count: int)

var resource_repo: ResourceRepository
var selection_manager: SelectionManager
var _pagination: PaginationManager

var rows: Array[ResourceRowVM] = []
var visible_columns: Array[ResourceProperty] = []
var sort_column: String = ""
var sort_ascending: bool = true
var search_filter: String = ""
var _visible_count: int = 0
var _total_pages: int = 1


func _init(presource_repo: ResourceRepository) -> void:
	resource_repo = presource_repo
	selection_manager = SelectionManager.new()
	_pagination = PaginationManager.new()

	resource_repo.resources_reseted.connect(_on_resources_reseted)
	resource_repo.resources_changed.connect(_on_resources_changed)
	resource_repo.resources_saved.connect(_on_resources_saved)
	selection_manager.selection_changed.connect(_on_selection_changed)


func request_sort(column: String) -> void:
	if column == sort_column:
		set_sort(column, not sort_ascending)
	else:
		set_sort(column, true)


func set_sort(column: String, ascending: bool) -> void:
	if sort_column == column and sort_ascending == ascending:
		return
	sort_column = column
	sort_ascending = ascending
	sort_state_changed.emit(column, ascending)
	if resource_repo.current_class_resources.is_empty():
		_emit_page_state()
		return
	_apply_sort()
	selection_manager.reconcile(resource_repo.get_paths())
	_pagination.reset(resource_repo.current_class_resources)
	_emit_page_state()


func handle_row_click(path: String, ctrl_held: bool, shift_held: bool) -> void:
	selection_manager.set_selected(path, ctrl_held, shift_held, resource_repo.get_paths())


func request_delete(paths: Array[String]) -> void:
	resource_repo.request_delete(paths)


func next_page() -> void:
	_pagination.next(resource_repo.current_class_resources)
	_emit_page_state()


func prev_page() -> void:
	_pagination.prev(resource_repo.current_class_resources)
	_emit_page_state()


func refresh_current_view() -> void:
	resource_repo.reload()


func get_current_page() -> int:
	return _pagination.current_page()


func get_total_pages() -> int:
	return _total_pages


func get_visible_count() -> int:
	return _visible_count


func get_selected_count() -> int:
	return selection_manager.selected_paths.size()


func is_path_selected(path: String) -> bool:
	return selection_manager.selected_paths.has(path)


func _on_resources_reseted(_resources: Array[Resource]) -> void:
	_rebuild_columns()
	_apply_sort()
	selection_manager.reconcile(resource_repo.get_paths())
	_pagination.reset(resource_repo.current_class_resources)
	_emit_page_state()


func _on_resources_changed(
	_added: Array[Resource], _removed: Array[Resource], _modified: Array[Resource]
) -> void:
	_apply_sort()
	selection_manager.reconcile(resource_repo.get_paths())
	_pagination.set_page(_pagination.current_page(), resource_repo.current_class_resources)
	_emit_page_state()


func _on_resources_saved(paths: Array[String]) -> void:
	var saved: Array[Resource] = []
	for path: String in paths:
		var res: Resource = resource_repo.get_by_path(path)
		if res:
			saved.append(res)
	if not saved.is_empty():
		rows_edited.emit(saved)


func _on_selection_changed(paths: Array[String]) -> void:
	_apply_selection_to_rows(paths)
	status_text_changed.emit(_visible_count, paths.size())


func _rebuild_columns() -> void:
	var selected: String = resource_repo.selected_class
	if selected.is_empty():
		visible_columns.clear()
		columns_changed.emit(Array([], TYPE_OBJECT, "RefCounted", ResourceProperty))
		return
	var included: Array[String] = resource_repo.class_registry.get_descendant_classes(
		selected, resource_repo.include_subclasses)
	visible_columns = resource_repo.class_registry.get_shared_properties(included)
	columns_changed.emit(visible_columns)
	_validate_sort_column()


func _apply_sort() -> void:
	ResourceSorter.sort(
		resource_repo.current_class_resources,
		sort_column,
		sort_ascending,
		visible_columns)


func _apply_selection_to_rows(paths: Array[String]) -> void:
	var selected: Dictionary[String, bool] = {}
	for path: String in paths:
		selected[path] = true
	for row_vm: ResourceRowVM in rows:
		row_vm.set_selected_state(selected.has(row_vm.resource.resource_path))


func _emit_page_state() -> void:
	_rebuild_rows(_pagination.current_page_resources)
	_visible_count = _pagination.current_page_resources.size()
	_total_pages = _pagination.page_count(resource_repo.current_class_resources.size())
	pagination_state_changed.emit(_pagination.current_page(), _total_pages)
	status_text_changed.emit(_visible_count, selection_manager.selected_paths.size())


func _rebuild_rows(resources: Array[Resource]) -> void:
	rows.clear()
	for res: Resource in resources:
		var row_vm: ResourceRowVM = ResourceRowVM.new(res, self)
		row_vm.set_selected_state(is_path_selected(res.resource_path))
		rows.append(row_vm)
	rows_replaced.emit(rows)


func _validate_sort_column() -> void:
	if sort_column.is_empty():
		return
	for prop: ResourceProperty in visible_columns:
		if prop.name == sort_column:
			return
	set_sort("", true)
