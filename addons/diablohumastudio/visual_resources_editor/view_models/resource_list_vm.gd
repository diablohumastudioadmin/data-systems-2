@tool
class_name ResourceListVM
extends RefCounted

signal rows_replaced(rows: Array[ResourceRowVM])
signal rows_edited(resources: Array[Resource])
signal columns_changed(columns: Array[ResourceProperty])
signal sort_state_changed(column: String, ascending: bool)
signal pagination_state_changed(page: int, total_pages: int)
signal status_text_changed(visible_count: int, selected_count: int)

var _model: VREModel
var _selection: SelectionManager
var _pagination: PaginationManager

var rows: Array[ResourceRowVM] = []
var visible_columns: Array[ResourceProperty] = []
var sort_column: String = ""
var sort_ascending: bool = true
var _visible_count: int = 0
var _total_pages: int = 1


func _init(p_model: VREModel) -> void:
	_model = p_model
	_selection = SelectionManager.new()
	_pagination = PaginationManager.new()
	sort_column = _model.session.sort_column
	sort_ascending = _model.session.sort_ascending

	_model.resource_repo.resources_reset.connect(_on_resources_reset)
	_model.resource_repo.resources_delta.connect(_on_resources_delta)
	_model.resources_edited.connect(func(res: Array[Resource]): rows_edited.emit(res))
	_model.session.sort_changed.connect(_on_sort_changed)
	_model.session.selected_paths_changed.connect(_on_session_selected_paths_changed)
	_selection.selection_changed.connect(_on_selection_manager_changed)


func request_sort(column: String) -> void:
	if column == sort_column:
		_model.session.set_sort(column, not sort_ascending)
	else:
		_model.session.set_sort(column, true)


func handle_row_click(path: String, ctrl_held: bool, shift_held: bool) -> void:
	_selection.set_selected(path, ctrl_held, shift_held, _model.resource_repo.get_paths())


func request_delete(paths: Array[String]) -> void:
	_model.request_delete_selected_resources(paths)


func next_page() -> void:
	_pagination.next(_model.resource_repo.current_class_resources)
	_emit_page_state()


func prev_page() -> void:
	_pagination.prev(_model.resource_repo.current_class_resources)
	_emit_page_state()


func get_current_page() -> int:
	return _pagination.current_page()


func get_total_pages() -> int:
	return _total_pages


func get_visible_count() -> int:
	return _visible_count


func get_selected_count() -> int:
	return _model.session.selected_paths.size()


func is_path_selected(path: String) -> bool:
	return _model.session.selected_paths.has(path)


func _on_sort_changed(column: String, ascending: bool) -> void:
	sort_column = column
	sort_ascending = ascending
	sort_state_changed.emit(column, ascending)
	if _model.resource_repo.current_class_resources.is_empty():
		_emit_page_state()
		return
	_apply_sort()
	_selection.reconcile(_model.resource_repo.get_paths())
	_pagination.reset(_model.resource_repo.current_class_resources)
	_emit_page_state()


func _on_resources_reset(_resources: Array[Resource]) -> void:
	visible_columns = _model.current_shared_property_list.duplicate()
	columns_changed.emit(visible_columns)
	_apply_sort()
	_selection.reconcile(_model.resource_repo.get_paths())
	_pagination.reset(_model.resource_repo.current_class_resources)
	_emit_page_state()


func _on_resources_delta(
	_added: Array[Resource], _removed: Array[Resource], _modified: Array[Resource]
) -> void:
	_apply_sort()
	_selection.reconcile(_model.resource_repo.get_paths())
	_pagination.set_page(_pagination.current_page(), _model.resource_repo.current_class_resources)
	_emit_page_state()


func _on_selection_manager_changed(paths: Array[String]) -> void:
	_model.session.selected_paths = paths
	_apply_selection_to_rows(paths)
	status_text_changed.emit(_visible_count, paths.size())


func _on_session_selected_paths_changed(paths: Array[String]) -> void:
	if paths == _selection.selected_paths:
		_apply_selection_to_rows(paths)
		status_text_changed.emit(_visible_count, paths.size())
		return
	if paths.is_empty():
		_selection.clear()
		return
	_selection.selected_paths = paths.duplicate()
	_apply_selection_to_rows(paths)
	status_text_changed.emit(_visible_count, paths.size())


func _apply_sort() -> void:
	ResourceSorter.sort(
		_model.resource_repo.current_class_resources,
		_model.session.sort_column,
		_model.session.sort_ascending,
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
	_total_pages = _pagination.page_count(_model.resource_repo.current_class_resources.size())
	_model.session.current_page = _pagination.current_page()
	pagination_state_changed.emit(_pagination.current_page(), _total_pages)
	status_text_changed.emit(_visible_count, _model.session.selected_paths.size())


func _rebuild_rows(resources: Array[Resource]) -> void:
	rows.clear()
	for res: Resource in resources:
		var row_vm: ResourceRowVM = ResourceRowVM.new(res, self)
		row_vm.set_selected_state(is_path_selected(res.resource_path))
		rows.append(row_vm)
	rows_replaced.emit(rows)
