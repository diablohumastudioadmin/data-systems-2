@tool
class_name ResourceList
extends VBoxContainer

const RESOURCE_ROW_SCENE: PackedScene = preload("uid://dukcnu4xa4lbd")

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()

var _rows: Array[ResourceRow] = []
var _resource_path_to_row: Dictionary[String, ResourceRow] = {}
var _current_shared_propery_list: Array[ResourceProperty] = []


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	state_manager.resources_replaced.connect(_on_state_manager_resources_replaced)

	state_manager.resources_added.connect(_on_state_manager_resources_added)
	state_manager.resources_modified.connect(_on_state_manager_resources_modified)
	state_manager.resources_removed.connect(_on_state_manager_resources_removed)

	state_manager.selection_changed.connect(_on_state_manager_selection_changed)
	state_manager.resources_edited.connect(_on_state_manager_resources_edited)

# ── State Manager Signal conections handlers ─────────────────────────────────────────────────────────────

func _on_state_manager_resources_added(resources: Array[Resource]):
	_add_resources(resources)
	_update_selection(state_manager.selected_resources)

func _on_state_manager_resources_modified(resources: Array[Resource]):
	_modify_resources(resources)
	_update_selection(state_manager.selected_resources)

func _on_state_manager_resources_removed(resources: Array[Resource]):
	_remove_resources(resources)
	_update_selection(state_manager.selected_resources)

func _on_state_manager_resources_replaced(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_build_rows(resources, current_shared_propery_list)

func _on_state_manager_selection_changed(selected_resources: Array[Resource]):
	_update_selection(selected_resources)

func _on_state_manager_resources_edited(resources: Array[Resource]):
	for res: Resource in resources:
		_refresh_row(res.resource_path)

# ── rows handling ─────────────────────────────────────────────────────────────

func _add_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_add_row(res)
	_sort_rows_by_path()

func _modify_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_update_row_resource(res)

func _remove_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		_remove_row_by_path(res.resource_path)

func _refresh_row(resource_path: String) -> void:
	if not _resource_path_to_row.has(resource_path):
		return
	var row: ResourceRow = _resource_path_to_row[resource_path]
	if is_instance_valid(row):
		row.update_display()


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

# ── slection handling ─────────────────────────────────────────────────────────────

func _update_selection(selected: Array[Resource]) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.set_selected(selected.has(row.get_resource()))

# ── Selection (visual only) ────────────────────────────────────────────────────

func _on_resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	state_manager.set_selected_resources(resource, ctrl_held, shift_held)
