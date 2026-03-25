@tool
class_name ResourceList
extends VBoxContainer

signal row_clicked(resource: Resource, ctrl_held: bool, shift_held: bool)

const RESOURCE_ROW_SCENE: PackedScene = preload("uid://dukcnu4xa4lbd")

var _rows: Array[ResourceRow] = []
var _resource_to_row: Dictionary = {}  # Resource → ResourceRow


# ── Public API ─────────────────────────────────────────────────────────────────

func set_data(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_build_rows(resources, current_shared_propery_list)


func refresh_row(resource_path: String) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row) and row.get_resource_path() == resource_path:
			row.update_display()
			break


func update_selection(selected: Array[Resource]) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.set_selected(selected.has(row.get_resource()))


# ── Table building ─────────────────────────────────────────────────────────────

func _build_rows(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_clear_rows()
	%HeaderRow.current_shared_propery_list = current_shared_propery_list

	for res: Resource in resources:
		var row: ResourceRow = RESOURCE_ROW_SCENE.instantiate()
		row.resource = res
		row.current_shared_propery_list = current_shared_propery_list
		%RowsContainer.add_child(row)
		row.resource_row_selected.connect(_on_resource_row_selected)
		_rows.append(row)
		_resource_to_row[res] = row


func _clear_rows() -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			if row.resource_row_selected.is_connected(_on_resource_row_selected):
				row.resource_row_selected.disconnect(_on_resource_row_selected)
			row.queue_free()
	_rows.clear()
	_resource_to_row.clear()


# ── Selection (visual only) ────────────────────────────────────────────────────

func _on_resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	row_clicked.emit(resource, ctrl_held, shift_held)
