@tool
extends Window

var _inspector_connected: bool = false
var _selected_resources: Array[Resource] = []
var _inspected_resource: Resource = null
var _bulk_proxy: Resource = null
var _current_class_name: String = ""


func _ready() -> void:
	%VREStateManager.data_changed.connect(_on_state_data_changed)

	_refresh_class_selector()
	%ClassSelector.class_selected.connect(_on_class_selected)
	%IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

	%ResourceList.rows_selected.connect(_on_rows_selected)
	%ResourceList.create_requested.connect(_on_create_requested)
	%ResourceList.delete_requested.connect(_on_delete_requested)
	%ResourceList.refresh_requested.connect(_on_refresh_requested)

	if Engine.is_editor_hint():
		var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if efs and not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)

	_connect_inspector()


func _exit_tree() -> void:
	_disconnect_inspector()
	if Engine.is_editor_hint():
		var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)


# ── Class selector ─────────────────────────────────────────────────────────────

func _refresh_class_selector() -> void:
	var classes: Array[Dictionary] = ProjectClassScanner.get_resource_classes_in_folder([], [])
	var names: Array = classes.map(func(c: Dictionary) -> String: return c.name as String)
	%ClassSelector._classes_names = names


func _on_class_selected(class_name_str: String) -> void:
	_current_class_name = class_name_str
	%VREStateManager.set_class(class_name_str)


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%VREStateManager.set_include_subclasses(pressed)


func _on_filesystem_changed() -> void:
	_refresh_class_selector()
	# StateManager handles resource list refresh independently via its own connection


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[Dictionary]) -> void:
	%ResourceList.set_data(resources, columns)


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_rows_selected(resources: Array[Resource]) -> void:
	_selected_resources = resources
	if resources.is_empty():
		return
	if resources.size() == 1:
		_bulk_proxy = null
		_inspected_resource = resources[0]
		EditorInterface.inspect_object(_inspected_resource)
	else:
		_inspected_resource = null
		_start_bulk_edit(resources)


func _start_bulk_edit(resources: Array[Resource]) -> void:
	var script: GDScript = resources[0].get_script()
	if script == null:
		return
	_bulk_proxy = script.new()
	for prop: Dictionary in script.get_script_property_list():
		_bulk_proxy.set(prop.name, resources[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)


# ── Inspector ──────────────────────────────────────────────────────────────────

func _connect_inspector() -> void:
	if _inspector_connected or not Engine.is_editor_hint():
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


func _on_inspector_property_edited(property: String) -> void:
	var inspector: EditorInspector = EditorInterface.get_inspector()
	if inspector == null:
		return
	var edited_obj: Object = inspector.get_edited_object()

	if _bulk_proxy and edited_obj == _bulk_proxy:
		var new_value: Variant = _bulk_proxy.get(property)
		for res: Resource in _selected_resources:
			res.set(property, new_value)
			ResourceSaver.save(res, res.resource_path)
			%ResourceList.refresh_row(res.resource_path)
		return

	if _inspected_resource and edited_obj == _inspected_resource:
		ResourceSaver.save(_inspected_resource, _inspected_resource.resource_path)
		%ResourceList.refresh_row(_inspected_resource.resource_path)


# ── CRUD ───────────────────────────────────────────────────────────────────────

func _on_create_requested() -> void:
	if _current_class_name.is_empty():
		return
	var parent_map: Dictionary = ProjectClassScanner.build_project_classes_parent_map()
	var script_path: String = parent_map.get(_current_class_name, "")
	if script_path.is_empty():
		return

	var dialog: EditorFileDialog = EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.tres")
	dialog.title = "Save New %s" % _current_class_name
	dialog.file_selected.connect(func(path: String) -> void:
		var script: GDScript = load(script_path)
		if script:
			ResourceSaver.save(script.new(), path)
			EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 500))


func _on_delete_requested(paths: Array[String]) -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "Delete %d resource(s)?\nThis cannot be undone.\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p: String) -> String: return p.get_file()))
	]
	dialog.confirmed.connect(func() -> void:
		for path: String in paths:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		EditorInterface.get_resource_filesystem().scan()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _on_refresh_requested() -> void:
	%VREStateManager.rescan()


func _on_close_requested() -> void:
	queue_free()
