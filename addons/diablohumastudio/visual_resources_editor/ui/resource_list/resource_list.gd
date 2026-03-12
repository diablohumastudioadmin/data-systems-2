@tool
extends VBoxContainer

const ResourceRowScene = preload("res://addons/diablohumastudio/visual_resources_editor/ui/resource_list/resource_row.tscn")

var _current_class_name: String = ""
var _current_script_path: String = ""
var _columns: Array[Dictionary] = []
var _loaded_resources: Dictionary = {}  # resource_path → Resource
var _rows: Array = []                   # ResourceRow nodes
var _inspected_path: String = ""
var _bulk_proxy: Resource = null
var _is_bulk_editing: bool = false
var _inspector_connected: bool = false


func _ready() -> void:
	%CreateBtn.pressed.connect(_on_create_pressed)
	%DeleteSelectedBtn.pressed.connect(_on_delete_selected_pressed)
	%RefreshBtn.pressed.connect(_on_refresh_pressed)
	%IncludeSubclassesCheck.toggled.connect(func(_v): _rescan_and_rebuild())

	_connect_inspector()


func _exit_tree() -> void:
	_disconnect_inspector()


func set_resource_class(class_name_str: String, script_path: String) -> void:
	_current_class_name = class_name_str
	_current_script_path = script_path
	_end_bulk_edit()
	_rescan_and_rebuild()


func refresh() -> void:
	if _current_class_name.is_empty():
		return
	_rescan_and_rebuild()


# ── Scanning ──────────────────────────────────────────────────────────────────

func _rescan_and_rebuild() -> void:
	if _current_class_name.is_empty():
		return

	_update_status("Scanning...")
	
	_columns = ProjectClassScanner.get_properties_from_script_path(_current_script_path)
	%HeaderRow.columns = _columns

	var paths: Array[String] = _get_classed_tres_paths_in_project()
	_build_rows(paths)
	
	_update_status("%d resource(s) found" % paths.size())

func _get_classed_tres_paths_in_project() -> Array[String]:
	var classes: Array = [_current_class_name]
	if %IncludeSubclassesCheck.button_pressed:
		classes.append_array(
			ProjectClassScanner.get_descendant_classes(_current_class_name)
		)

	var root: EditorFileSystemDirectory = EditorInterface \
		.get_resource_filesystem().get_filesystem()
	var results: Array[String] = ProjectClassScanner \
		.scan_folder_for_classed_tres(root, classes)
	results.sort()
	return results


# ── Table building ────────────────────────────────────────────────────────────

func _build_rows(paths: Array[String]) -> void:
	_clear_rows()
	_loaded_resources.clear()
	_inspected_path = ""

	for path: String in paths:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null:
			continue

		_loaded_resources[path] = res
		var row: ResourceRow = ResourceRowScene.instantiate()
		row.resource = res
		row.columns = _columns
		%RowsContainer.add_child(row)
		row.row_clicked.connect(_on_row_clicked)
		row.delete_requested.connect(_on_row_delete_requested)
		_rows.append(row)


func _clear_rows() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()


# ── Inspector integration ─────────────────────────────────────────────────────

func _connect_inspector() -> void:
	if _inspector_connected:
		return
	if not Engine.is_editor_hint():
		return
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector:
		inspector.property_edited.connect(_on_inspector_property_edited)
		_inspector_connected = true


func _disconnect_inspector() -> void:
	if not _inspector_connected:
		return
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector and inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.disconnect(_on_inspector_property_edited)
	_inspector_connected = false


func _on_row_clicked(row: ResourceRow, shift_held: bool) -> void:
	if shift_held:
		row.set_selected(!row.is_selected())
	else:
		_end_bulk_edit()
		for r in _rows:
			if is_instance_valid(r):
				r.set_selected(r == row)
		_inspected_path = row.get_resource_path()
		var res: Resource = _loaded_resources.get(_inspected_path)
		if res:
			EditorInterface.inspect_object(res)

	var selected: Array = _get_selected_rows()
	if selected.size() >= 2:
		_start_bulk_edit_all(selected)
	elif not shift_held:
		_end_bulk_edit()

	_update_selection_ui()


func _on_inspector_property_edited(property: String) -> void:
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector == null:
		return
	var edited_obj: Object = inspector.get_edited_object()

	if edited_obj != _bulk_proxy and not _loaded_resources.values().has(edited_obj):
		return

	if _is_bulk_editing and _bulk_proxy and edited_obj == _bulk_proxy:
		var new_value: Variant = _bulk_proxy.get(property)
		for row in _get_selected_rows():
			var res: Resource = row.get_resource()
			if res:
				res.set(property, new_value)
				ResourceSaver.save(res, row.get_resource_path())
				row.update_display()
		return

	if _inspected_path.is_empty():
		return
	var expected_res: Resource = _loaded_resources.get(_inspected_path)
	if edited_obj == null or edited_obj != expected_res:
		return

	ResourceSaver.save(expected_res, _inspected_path)

	for row in _rows:
		if is_instance_valid(row) and row.get_resource_path() == _inspected_path:
			row.update_display()
			break


# ── Selection & Bulk Edit ─────────────────────────────────────────────────────

func _update_selection_ui() -> void:
	var selected_count: int = _get_selected_rows().size()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % selected_count if selected_count > 0 else "Delete Selected"
	if selected_count > 0:
		_update_status("%d selected" % selected_count)
	else:
		_update_status("%d resource(s)" % _rows.size())


func _get_selected_rows() -> Array:
	var selected: Array = []
	for row in _rows:
		if is_instance_valid(row) and row.is_selected():
			selected.append(row)
	return selected


func _start_bulk_edit_all(selected: Array) -> void:
	_end_bulk_edit()
	if _current_script_path.is_empty():
		return

	var script: GDScript = load(_current_script_path)
	if script == null:
		return

	_bulk_proxy = script.new()
	var first_res: Resource = selected[0].get_resource()
	if first_res:
		for col: Dictionary in _columns:
			_bulk_proxy.set(col.name, first_res.get(col.name))

	_is_bulk_editing = true
	EditorInterface.inspect_object(_bulk_proxy)
	_update_status("Bulk editing %d instances" % selected.size())


func _end_bulk_edit() -> void:
	_bulk_proxy = null
	_is_bulk_editing = false


# ── CRUD ──────────────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	if _current_script_path.is_empty():
		return

	var dialog: EditorFileDialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres")
	dialog.title = "Save New %s" % _current_class_name

	dialog.file_selected.connect(func(path: String):
		var script: GDScript = load(_current_script_path)
		if script:
			var res: Resource = script.new()
			ResourceSaver.save(res, path)
			EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


func _on_row_delete_requested(resource_path: String) -> void:
	_confirm_delete([resource_path])


func _on_delete_selected_pressed() -> void:
	var selected: Array = _get_selected_rows()
	if selected.is_empty():
		return
	var paths: Array[String] = []
	for row in selected:
		paths.append(row.get_resource_path())
	_confirm_delete(paths)


func _confirm_delete(paths: Array[String]) -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete %d resource(s)?\nThis cannot be undone.\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p): return p.get_file()))
	]

	dialog.confirmed.connect(func():
		for path: String in paths:
			DirAccess.remove_absolute(path)
			_loaded_resources.erase(path)
		EditorInterface.get_resource_filesystem().scan()
		_end_bulk_edit()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _on_refresh_pressed() -> void:
	_rescan_and_rebuild()


# ── Status Label ────────────────────────────────────────────────────────────────────

func _update_status(text: String) -> void:
	%StatusLabel.text = text
