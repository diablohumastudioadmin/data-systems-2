@tool
class_name ResourceList
extends VBoxContainer

signal row_clicked(resource: Resource, ctrl_held: bool, shift_held: bool)

const RESOURCE_ROW_SCENE: PackedScene = preload("uid://dukcnu4xa4lbd")

var _rows: Array[ResourceRow] = []
var _resource_path_to_row: Dictionary[String, ResourceRow] = {}
var _current_shared_propery_list: Array[ResourceProperty] = []


func initialize(state: VREStateManager) -> void:
	row_clicked.connect(state.set_selected_resources)
	state.resources_replaced.connect(replace_resources)
	state.resources_added.connect(func(resources: Array[Resource]) -> void:
		add_resources(resources)
		update_selection(state.selected_resources)
	)
	state.resources_modified.connect(func(resources: Array[Resource]) -> void:
		modify_resources(resources)
		update_selection(state.selected_resources)
	)
	state.resources_removed.connect(func(resources: Array[Resource]) -> void:
		remove_resources(resources)
		update_selection(state.selected_resources)
	)
	state.selection_changed.connect(update_selection)
	state.resources_edited.connect(func(resources: Array[Resource]) -> void:
		for res: Resource in resources:
			refresh_row(res.resource_path)
	)


# ── Public API ─────────────────────────────────────────────────────────────────

func replace_resources(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_build_rows(resources, current_shared_propery_list)


func add_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_add_row(res)
	_sort_rows_by_path()


func modify_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_update_row_resource(res)


func remove_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_remove_row_by_path(res.resource_path)


func get_row_count() -> int:
	return _rows.size()


func refresh_row(resource_path: String) -> void:
	if not _resource_path_to_row.has(resource_path):
		return
	var row: ResourceRow = _resource_path_to_row[resource_path]
	if is_instance_valid(row):
		row.update_display()


func update_selection(selected: Array[Resource]) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.set_selected(selected.has(row.get_resource()))


# ── Table building ─────────────────────────────────────────────────────────────

func _build_rows(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_clear_rows()
	_current_shared_propery_list = current_shared_propery_list
	%HeaderRow.current_shared_propery_list = current_shared_propery_list

	for res: Resource in resources:
		_add_row(res)

	_sort_rows_by_path()


func _clear_rows() -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			if row.resource_row_selected.is_connected(_on_resource_row_selected):
				row.resource_row_selected.disconnect(_on_resource_row_selected)
			row.queue_free()
	_rows.clear()
	_resource_path_to_row.clear()


func _add_row(res: Resource) -> void:
	if _resource_path_to_row.has(res.resource_path):
		return
	var row: ResourceRow = RESOURCE_ROW_SCENE.instantiate()
	row.resource = res
	row.current_shared_propery_list = _current_shared_propery_list
	%RowsContainer.add_child(row)
	row.resource_row_selected.connect(_on_resource_row_selected)
	_rows.append(row)
	_resource_path_to_row[res.resource_path] = row


func _remove_row_by_path(resource_path: String) -> void:
	if not _resource_path_to_row.has(resource_path):
		return
	var row: ResourceRow = _resource_path_to_row[resource_path]
	if is_instance_valid(row):
		if row.resource_row_selected.is_connected(_on_resource_row_selected):
			row.resource_row_selected.disconnect(_on_resource_row_selected)
		_rows.erase(row)
		row.queue_free()
	_resource_path_to_row.erase(resource_path)


func _update_row_resource(resource: Resource) -> void:
	if not _resource_path_to_row.has(resource.resource_path):
		return
	var row: ResourceRow = _resource_path_to_row[resource.resource_path]
	if is_instance_valid(row):
		row.resource = resource
		row.update_display()


func _sort_rows_by_path() -> void:
	_rows.sort_custom(func(a: ResourceRow, b: ResourceRow) -> bool: return a.get_resource_path() < b.get_resource_path())
	for i: int in _rows.size():
		var row: ResourceRow = _rows[i]
		if is_instance_valid(row):
			%RowsContainer.move_child(row, i)


# ── Selection (visual only) ────────────────────────────────────────────────────

func _on_resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	row_clicked.emit(resource, ctrl_held, shift_held)
