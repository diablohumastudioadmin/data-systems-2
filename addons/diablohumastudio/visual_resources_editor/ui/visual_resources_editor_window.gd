@tool
extends Window


func _ready() -> void:
	_refresh_class_selector()

	%VREStateManager.data_changed.connect(_on_state_data_changed)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

	%ResourceList.rows_selected.connect(_on_rows_selected)
	%ResourceList.create_requested.connect(%ResourceCRUD.create)
	%ResourceList.delete_requested.connect(%ResourceCRUD.delete)
	%ResourceList.refresh_requested.connect(%VREStateManager.rescan)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


# ── Class selector ─────────────────────────────────────────────────────────────

func _refresh_class_selector() -> void:
	%ClassSelector._classes_names = %VREStateManager.project_resource_classes


func _on_class_selected(class_name_str: String) -> void:
	%VREStateManager.set_class(class_name_str)
	%BulkEditor.current_class_name = class_name_str
	%ResourceCRUD.current_class_name = class_name_str


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%VREStateManager.set_include_subclasses(pressed)
	%SubclassWarningLabel.visible = pressed


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[Dictionary]) -> void:
	%ResourceList.set_data(resources, columns)
	_refresh_class_selector()


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_rows_selected(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources


func _on_close_requested() -> void:
	queue_free()
