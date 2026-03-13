@tool
extends VBoxContainer

signal rows_selected(resources: Array[Resource])
signal create_requested
signal delete_requested(paths: Array[String])
signal refresh_requested

const ResourceRowScene = preload(
	"res://addons/diablohumastudio/visual_resources_editor/ui/resource_list/resource_row.tscn"
)

var selected_rows: Array[Resource] = []
var _rows: Array = []              # ResourceRow nodes
var _resource_to_row: Dictionary = {}  # Resource → ResourceRow


func _ready() -> void:
	%CreateBtn.pressed.connect(func(): create_requested.emit())
	%DeleteSelectedBtn.pressed.connect(_on_delete_selected_pressed)
	%RefreshBtn.pressed.connect(func(): refresh_requested.emit())


# ── Public API ─────────────────────────────────────────────────────────────────

func set_data(resources: Array[Resource], columns: Array[Dictionary]) -> void:
	selected_rows.clear()
	_build_rows(resources, columns)
	_update_selection_ui()


func refresh_row(resource_path: String) -> void:
	for row in _rows:
		if is_instance_valid(row) and row.get_resource_path() == resource_path:
			row.update_display()
			break


# ── Table building ─────────────────────────────────────────────────────────────

func _build_rows(resources: Array[Resource], columns: Array[Dictionary]) -> void:
	_clear_rows()
	%HeaderRow.columns = columns

	for res: Resource in resources:
		var row: ResourceRow = ResourceRowScene.instantiate()
		row.resource = res
		row.columns = columns
		%RowsContainer.add_child(row)
		row.resource_row_selected.connect(_on_resource_row_selected)
		row.delete_requested.connect(_on_row_delete_requested)
		_rows.append(row)
		_resource_to_row[res] = row

	_update_status("%d resource(s) found" % resources.size())


func _clear_rows() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()
	_resource_to_row.clear()


# ── Selection ──────────────────────────────────────────────────────────────────

func _on_resource_row_selected(resource: Resource, shift_held: bool) -> void:
	if shift_held:
		if selected_rows.has(resource):
			selected_rows.erase(resource)
			_resource_to_row[resource].set_selected(false)
		else:
			selected_rows.append(resource)
			_resource_to_row[resource].set_selected(true)
	else:
		for res: Resource in selected_rows:
			if _resource_to_row.has(res) and is_instance_valid(_resource_to_row[res]):
				_resource_to_row[res].set_selected(false)
		selected_rows.clear()
		selected_rows.append(resource)
		_resource_to_row[resource].set_selected(true)

	_update_selection_ui()
	rows_selected.emit(selected_rows.duplicate())


func _update_selection_ui() -> void:
	var count: int = selected_rows.size()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 else "Delete Selected"
	if count > 0:
		_update_status("%d selected" % count)
	else:
		_update_status("%d resource(s)" % _rows.size())


# ── CRUD ───────────────────────────────────────────────────────────────────────

func _on_row_delete_requested(resource_path: String) -> void:
	var paths: Array[String] = []
	paths.append(resource_path)
	delete_requested.emit(paths)


func _on_delete_selected_pressed() -> void:
	if selected_rows.is_empty():
		return
	var paths: Array[String] = []
	for res: Resource in selected_rows:
		paths.append(res.resource_path)
	delete_requested.emit(paths)


# ── Status ─────────────────────────────────────────────────────────────────────

func _update_status(text: String) -> void:
	%StatusLabel.text = text
