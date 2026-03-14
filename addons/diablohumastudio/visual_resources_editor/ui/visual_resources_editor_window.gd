@tool
extends Window


func _ready() -> void:
	%ClassSelector.set_classes(%VREStateManager.project_resource_classes)

	%VREStateManager.data_changed.connect(_on_state_data_changed)
	%VREStateManager.project_classes_changed.connect(_on_project_classes_changed)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

	%ResourceList.rows_selected.connect(_on_rows_selected)
	%ResourceList.create_requested.connect(%SaveResourceDialog.show_create_dialog)
	%ResourceList.delete_requested.connect(%ConfirmDeleteDialog.show_delete_dialog)
	%ResourceList.refresh_requested.connect(%VREStateManager.rescan)

	%SaveResourceDialog.error_occurred.connect(%ErrorDialog.show_error)
	%ConfirmDeleteDialog.error_occurred.connect(%ErrorDialog.show_error)
	%BulkEditor.error_occurred.connect(%ErrorDialog.show_error)
	%BulkEditor.resources_edited.connect(_on_resources_edited)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


# ── Class selector ─────────────────────────────────────────────────────────────

func _on_class_selected(class_name_str: String) -> void:
	%VREStateManager.set_class(class_name_str)
	%BulkEditor.current_class_name = class_name_str
	%SaveResourceDialog.current_class_name = class_name_str


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%VREStateManager.set_include_subclasses(pressed)
	%SubclassWarningLabel.visible = pressed


func _on_project_classes_changed(added: Array[String], removed: Array[String]) -> void:
	for cls: String in added:
		%ClassSelector.add_class(cls)
	for cls: String in removed:
		%ClassSelector.remove_class(cls)


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[Dictionary]) -> void:
	%ResourceList.set_data(resources, columns)


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_rows_selected(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources


func _on_resources_edited(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		%ResourceList.refresh_row(res.resource_path)


func _on_close_requested() -> void:
	queue_free()
