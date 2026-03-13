@tool
extends Window

var _current_class_name: String = ""


func _ready() -> void:
	_refresh_class_selector()

	%VREStateManager.data_changed.connect(_on_state_data_changed)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

	%ResourceList.rows_selected.connect(_on_rows_selected)
	%ResourceList.create_requested.connect(_on_create_requested)
	%ResourceList.delete_requested.connect(_on_delete_requested)
	%ResourceList.refresh_requested.connect(_on_refresh_requested)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()

# ── Class selector ─────────────────────────────────────────────────────────────

func _refresh_class_selector() -> void:
	var classes: Array[Dictionary] = ProjectClassScanner.get_resource_classes_in_folder([], [])
	var names: Array = classes.map(func(c: Dictionary) -> String: return c.name as String)
	%ClassSelector._classes_names = names


func _on_class_selected(class_name_str: String) -> void:
	_current_class_name = class_name_str
	%VREStateManager.set_class(class_name_str)
	%BulkEditor.current_class_name = class_name_str


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%VREStateManager.set_include_subclasses(pressed)


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[Dictionary]) -> void:
	%ResourceList.set_data(resources, columns)
	_refresh_class_selector()


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_rows_selected(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources


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
