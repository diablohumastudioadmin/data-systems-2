@tool
class_name ResourceList
extends VBoxContainer

const RESOURCE_ROW_SCENE: PackedScene = preload("uid://dukcnu4xa4lbd")

var vm: ResourceListVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()

var _rows: Array[ResourceRow] = []
var _resource_path_to_row: Dictionary[String, ResourceRow] = {}
var _resource_path_to_row_vm: Dictionary[String, ResourceRowVM] = {}
var _current_shared_property_list: Array[ResourceProperty] = []


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.columns_changed.connect(_on_columns_changed)
	vm.rows_replaced.connect(_on_rows_replaced)
	vm.rows_added.connect(_on_rows_added)
	vm.rows_removed.connect(_on_rows_removed)
	vm.rows_modified.connect(_on_rows_modified)
	vm.rows_edited.connect(_on_rows_edited)
	%HeaderRow.set_view_model(vm)


func _on_columns_changed(columns: Array[ResourceProperty]) -> void:
	_current_shared_property_list = columns
	%HeaderRow.current_shared_property_list = columns
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.current_shared_property_list = columns
			row.rebuild_fields()


func _on_rows_replaced(rows: Array[ResourceRowVM]) -> void:
	_clear_rows()
	for row_vm: ResourceRowVM in rows:
		_add_row(row_vm)


func _on_rows_added(rows: Array[ResourceRowVM]) -> void:
	for row_vm: ResourceRowVM in rows:
		_add_row(row_vm)


func _on_rows_removed(removed_resources: Array[Resource]) -> void:
	for res: Resource in removed_resources:
		_remove_row_by_path(res.resource_path)


func _on_rows_modified(modified_resources: Array[Resource]) -> void:
	for res: Resource in modified_resources:
		var path: String = res.resource_path
		if _resource_path_to_row_vm.has(path):
			_resource_path_to_row_vm[path].resource = res
		if _resource_path_to_row.has(path):
			var row: ResourceRow = _resource_path_to_row[path]
			if is_instance_valid(row):
				row.update_display()


func _on_rows_edited(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		var path: String = res.resource_path
		if _resource_path_to_row.has(path):
			var row: ResourceRow = _resource_path_to_row[path]
			if is_instance_valid(row):
				row.update_display()


func _add_row(row_vm: ResourceRowVM) -> void:
	var path: String = row_vm.resource.resource_path
	if _resource_path_to_row.has(path):
		return
	var row: ResourceRow = RESOURCE_ROW_SCENE.instantiate()
	row.vm = row_vm
	row.current_shared_property_list = _current_shared_property_list
	%RowsContainer.add_child(row)
	_rows.append(row)
	_resource_path_to_row[path] = row
	_resource_path_to_row_vm[path] = row_vm


func _remove_row_by_path(resource_path: String) -> void:
	if not _resource_path_to_row.has(resource_path):
		return
	var row: ResourceRow = _resource_path_to_row[resource_path]
	if is_instance_valid(row):
		_rows.erase(row)
		row.queue_free()
	_resource_path_to_row.erase(resource_path)
	_resource_path_to_row_vm.erase(resource_path)


func _clear_rows() -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()
	_resource_path_to_row.clear()
	_resource_path_to_row_vm.clear()


