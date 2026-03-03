@tool
extends VBoxContainer

signal resource_clicked(resource: Resource)

const ResourceRowScene = preload("res://addons/diablohumastudio/visual_resources_editor/ui/resource_list/resource_row.tscn")
const BulkEditProxyScript = preload("res://addons/diablohumastudio/visual_resources_editor/ui/bulk_edit_proxy.gd")

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

	_setup_bulk_edit_menu()
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
	_columns = _get_property_columns()
	var paths: Array[String] = _scan_project_for_class()
	_build_header_row()
	_build_rows(paths)
	_update_bulk_edit_popup()
	_update_status("%d resource(s) found" % paths.size())


func _scan_project_for_class() -> Array[String]:
	var valid_classes: Dictionary = _build_valid_class_set()
	var results: Array[String] = []
	_scan_dir_recursive("res://", valid_classes, results)
	results.sort()
	return results


func _scan_dir_recursive(dir_path: String, valid_classes: Dictionary, results: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path: String
		if dir_path == "res://":
			full_path = dir_path + file_name
		else:
			full_path = dir_path.path_join(file_name)

		if dir.current_is_dir():
			if file_name != "addons":
				_scan_dir_recursive(full_path, valid_classes, results)
		elif file_name.ends_with(".tres"):
			var cls: String = _read_tres_class(full_path)
			if valid_classes.has(cls):
				results.append(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


func _read_tres_class(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var header: String = f.get_buffer(500).get_string_from_utf8()
	f.close()

	var sc_idx: int = header.find('script_class="')
	if sc_idx >= 0:
		var start: int = sc_idx + 14
		var end: int = header.find('"', start)
		if end > start:
			return header.substr(start, end - start)

	var t_idx: int = header.find('type="')
	if t_idx >= 0:
		var start: int = t_idx + 6
		var end: int = header.find('"', start)
		if end > start:
			return header.substr(start, end - start)

	return ""


func _build_valid_class_set() -> Dictionary:
	var valid: Dictionary = {}
	valid[_current_class_name] = true

	if not %IncludeSubclassesCheck.button_pressed:
		return valid

	var class_entries: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if not cls.is_empty():
			class_entries[cls] = entry.get("base", "")

	var changed: bool = true
	while changed:
		changed = false
		for cls: String in class_entries:
			if not valid.has(cls) and valid.has(class_entries[cls]):
				valid[cls] = true
				changed = true

	return valid


# ── Property columns ─────────────────────────────────────────────────────────

func _get_property_columns() -> Array[Dictionary]:
	var columns: Array[Dictionary] = []
	if _current_script_path.is_empty():
		return columns

	var script: GDScript = load(_current_script_path)
	if script == null:
		return columns

	var temp_instance: Resource = script.new()
	if temp_instance == null:
		return columns

	for prop: Dictionary in temp_instance.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var prop_name: String = prop.name
		if prop_name.begins_with("resource_") or prop_name.begins_with("metadata/"):
			continue
		if prop_name in ["script", "resource_local_to_scene"]:
			continue
		columns.append({
			"name": prop_name,
			"type": prop.type,
			"hint": prop.get("hint", PROPERTY_HINT_NONE),
			"hint_string": prop.get("hint_string", ""),
		})

	return columns


# ── Table building ────────────────────────────────────────────────────────────

func _build_header_row() -> void:
	for child in %HeaderRow.get_children():
		child.queue_free()

	var file_label: Label = Label.new()
	file_label.text = "File"
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.custom_minimum_size = Vector2(150, 0)
	file_label.add_theme_font_size_override("font_size", 12)
	%HeaderRow.add_child(file_label)

	for col: Dictionary in _columns:
		var sep: VSeparator = VSeparator.new()
		%HeaderRow.add_child(sep)

		var lbl: Label = Label.new()
		lbl.text = col.name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", 12)
		%HeaderRow.add_child(lbl)

	var sep_del: VSeparator = VSeparator.new()
	%HeaderRow.add_child(sep_del)

	var del_spacer: Control = Control.new()
	del_spacer.custom_minimum_size = Vector2(28, 0)
	%HeaderRow.add_child(del_spacer)


func _build_rows(paths: Array[String]) -> void:
	_clear_rows()
	_loaded_resources.clear()
	_inspected_path = ""

	for path: String in paths:
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			continue

		_loaded_resources[path] = res
		var row: HBoxContainer = ResourceRowScene.instantiate()
		%RowsContainer.add_child(row)
		row.setup(res, _columns)
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


func _on_row_clicked(resource_path: String, ctrl_held: bool) -> void:
	if ctrl_held:
		for row in _rows:
			if is_instance_valid(row) and row.get_resource_path() == resource_path:
				row.set_selected(!row.is_selected())
				break
	else:
		for row in _rows:
			if is_instance_valid(row):
				row.set_selected(row.get_resource_path() == resource_path)

		if not _is_bulk_editing:
			var res: Resource = _loaded_resources.get(resource_path)
			if res:
				_inspected_path = resource_path
				EditorInterface.inspect_object(res)
				resource_clicked.emit(res)

	_update_selection_ui()


func _on_inspector_property_edited(_property: String) -> void:
	if _is_bulk_editing or _inspected_path.is_empty():
		return

	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector == null:
		return
	var edited_obj: Object = inspector.get_edited_object()
	var expected_res: Resource = _loaded_resources.get(_inspected_path)
	if edited_obj == null or edited_obj != expected_res:
		return

	ResourceSaver.save(expected_res, _inspected_path)

	for row in _rows:
		if is_instance_valid(row) and row.get_resource_path() == _inspected_path:
			row.update_display()
			break


func _is_column_property(property: String) -> bool:
	for col: Dictionary in _columns:
		if col.name == property:
			return true
	return false


# ── Selection & Bulk Edit ─────────────────────────────────────────────────────

func _update_selection_ui() -> void:
	var selected_count: int = _get_selected_rows().size()
	%BulkEditBtn.disabled = selected_count < 2
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


func _setup_bulk_edit_menu() -> void:
	var popup: PopupMenu = %BulkEditBtn.get_popup()
	if popup.id_pressed.is_connected(_on_bulk_edit_field_selected):
		popup.id_pressed.disconnect(_on_bulk_edit_field_selected)
	popup.id_pressed.connect(_on_bulk_edit_field_selected)


func _on_bulk_edit_field_selected(id: int) -> void:
	if id >= _columns.size():
		return
	_start_bulk_edit(_columns[id])


func _start_bulk_edit(col: Dictionary) -> void:
	_end_bulk_edit()
	_is_bulk_editing = true

	var selected: Array = _get_selected_rows()
	var initial_value: Variant = null
	if selected.size() > 0:
		var res: Resource = selected[0].get_resource()
		if res:
			initial_value = res.get(col.name)

	_bulk_proxy = BulkEditProxyScript.new()
	_bulk_proxy.setup(col.name, col.type, initial_value, col.hint, col.hint_string)
	_bulk_proxy.value_changed.connect(_on_bulk_value_changed)

	EditorInterface.inspect_object(_bulk_proxy)
	_update_status("Bulk editing '%s' for %d instances" % [col.name, selected.size()])


func _on_bulk_value_changed(field_name: String, new_value: Variant) -> void:
	for row in _get_selected_rows():
		var res: Resource = row.get_resource()
		if res:
			res.set(field_name, new_value)
			ResourceSaver.save(res, row.get_resource_path())
			row.update_display()


func _end_bulk_edit() -> void:
	if _bulk_proxy:
		if _bulk_proxy.value_changed.is_connected(_on_bulk_value_changed):
			_bulk_proxy.value_changed.disconnect(_on_bulk_value_changed)
		_bulk_proxy = null
	_is_bulk_editing = false


# ── CRUD ──────────────────────────────────────────────────────────────────────

func _on_create_pressed() -> void:
	if _current_script_path.is_empty():
		return

	var dialog: EditorFileDialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres", "Resource File")
	dialog.title = "Save New %s" % _current_class_name

	dialog.file_selected.connect(func(path: String):
		var script: GDScript = load(_current_script_path)
		if script:
			var res: Resource = script.new()
			ResourceSaver.save(res, path)
			EditorInterface.get_resource_filesystem().scan()
			_rescan_and_rebuild.call_deferred()
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
		_rescan_and_rebuild.call_deferred()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()


func _on_refresh_pressed() -> void:
	_rescan_and_rebuild()


# ── Bulk edit menu population ─────────────────────────────────────────────────

func _update_bulk_edit_popup() -> void:
	var popup: PopupMenu = %BulkEditBtn.get_popup()
	popup.clear()
	for i in range(_columns.size()):
		popup.add_item(_columns[i].name, i)


# ── Status ────────────────────────────────────────────────────────────────────

func _update_status(text: String) -> void:
	%StatusLabel.text = text
