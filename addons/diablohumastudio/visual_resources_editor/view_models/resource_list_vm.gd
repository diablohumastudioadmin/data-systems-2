@tool
class_name ResourceListVM
extends RefCounted

signal rows_replaced(rows: Array[ResourceRowVM])
signal rows_added(rows: Array[ResourceRowVM])
signal rows_removed(removed_resources: Array[Resource])
signal rows_modified(modified_resources: Array[Resource])
signal rows_edited(resources: Array[Resource])
signal columns_changed(columns: Array[ResourceProperty])

var _model: VREModel
var rows: Array[ResourceRowVM] = []
var visible_columns: Array[ResourceProperty] = []

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.resources_replaced.connect(_on_resources_replaced)
	_model.resources_added.connect(_on_resources_added)
	_model.resources_removed.connect(_on_resources_removed)
	_model.resources_modified.connect(_on_resources_modified)
	_model.resources_edited.connect(func(res: Array[Resource]): rows_edited.emit(res))

func _on_resources_replaced(resources: Array[Resource], shared_properties: Array[ResourceProperty]) -> void:
	visible_columns = shared_properties
	columns_changed.emit(visible_columns)
	
	rows.clear()
	for res in resources:
		rows.append(ResourceRowVM.new(res, _model))
	rows_replaced.emit(rows)

func _on_resources_added(resources: Array[Resource]) -> void:
	var new_rows: Array[ResourceRowVM] = []
	for res in resources:
		var row: ResourceRowVM = ResourceRowVM.new(res, _model)
		rows.append(row)
		new_rows.append(row)
	rows_added.emit(new_rows)

func _on_resources_removed(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		rows = rows.filter(func(row_vm: ResourceRowVM) -> bool: return row_vm.resource != res)
	rows_removed.emit(resources)

func _on_resources_modified(resources: Array[Resource]) -> void:
	rows_modified.emit(resources)
