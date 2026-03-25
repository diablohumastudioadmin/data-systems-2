@tool
class_name ResourceList
extends VBoxContainer

signal row_clicked(resource: Resource, ctrl_held: bool, shift_held: bool)
signal prev_page_requested
signal next_page_requested

const RESOURCE_ROW_SCENE: PackedScene = preload("uid://dukcnu4xa4lbd")

var _rows: Array[ResourceRow] = []
var _resource_to_row: Dictionary = {}  # Resource → ResourceRow
var _visible_count: int = 0


func _ready() -> void:
	%PrevBtn.pressed.connect(prev_page_requested.emit)
	%NextBtn.pressed.connect(next_page_requested.emit)


# ── Public API ─────────────────────────────────────────────────────────────────

func set_data(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	_build_rows(resources, current_shared_propery_list)
	_update_status("%d resource(s)" % _visible_count)


func refresh_row(resource_path: String) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row) and row.get_resource_path() == resource_path:
			row.update_display()
			break


func update_selection(selected: Array[Resource]) -> void:
	for row: ResourceRow in _rows:
		if is_instance_valid(row):
			row.set_selected(selected.has(row.get_resource()))
	var count: int = selected.size()
	if count > 0:
		_update_status("%d selected" % count)
	else:
		_update_status("%d resource(s)" % _visible_count)


func update_pagination_bar(page: int, page_count: int) -> void:
	%PaginationBar.visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1


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


# ── Status ─────────────────────────────────────────────────────────────────────

func _update_status(text: String) -> void:
	%StatusLabel.text = text
