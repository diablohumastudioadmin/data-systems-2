@tool
class_name ResourceListVM
extends RefCounted

signal rows_replaced(rows: Array[ResourceRowVM])
signal rows_added(rows: Array[ResourceRowVM])
signal rows_removed(removed_resources: Array[Resource])
signal rows_modified(modified_resources: Array[Resource])
signal rows_edited(resources: Array[Resource])
signal columns_changed(columns: Array[ResourceProperty])
signal sort_state_changed(column: String, ascending: bool)

var _model: VREModel
var rows: Array[ResourceRowVM] = []
var visible_columns: Array[ResourceProperty] = []
var sort_column: String = ""
var sort_ascending: bool = true

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.resources_replaced.connect(_on_resources_replaced)
	_model.resources_added.connect(_on_resources_added)
	_model.resources_removed.connect(_on_resources_removed)
	_model.resources_modified.connect(_on_resources_modified)
	_model.resources_edited.connect(func(res: Array[Resource]): rows_edited.emit(res))
	_model.session.sort_changed.connect(_on_sort_changed)


func request_sort(column: String) -> void:
	if column == sort_column:
		_model.session.set_sort(column, not sort_ascending)
	else:
		_model.session.set_sort(column, true)


func _on_sort_changed(column: String, ascending: bool) -> void:
	sort_column = column
	sort_ascending = ascending
	sort_state_changed.emit(column, ascending)

func _on_resources_replaced(resources: Array[Resource], shared_properties: Array[ResourceProperty]) -> void:
	visible_columns = shared_properties
	columns_changed.emit(visible_columns)
	_rebuild_rows(resources)

func _on_resources_added(resources: Array[Resource]) -> void:
	if resources.is_empty():
		return
	_rebuild_rows(_model.current_page_resources)

func _on_resources_removed(resources: Array[Resource]) -> void:
	if resources.is_empty():
		return
	_rebuild_rows(_model.current_page_resources)

func _on_resources_modified(resources: Array[Resource]) -> void:
	if resources.is_empty():
		return
	_rebuild_rows(_model.current_page_resources)


func _rebuild_rows(resources: Array[Resource]) -> void:
	for row_vm: ResourceRowVM in rows:
		row_vm.dispose()
	rows.clear()
	for res: Resource in resources:
		rows.append(ResourceRowVM.new(res, _model))
	rows_replaced.emit(rows)
