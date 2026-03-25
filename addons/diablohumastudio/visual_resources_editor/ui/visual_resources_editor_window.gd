@tool
class_name VisualResourcesEditorWindow
extends Window

var error_dialog: ErrorDialog


func create_and_add_dialogs() -> void:
	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)


func connect_components() -> void:
	%VREStateManager.data_changed.connect(_on_state_data_changed)
	%VREStateManager.project_classes_changed.connect(_on_project_classes_changed)
	%VREStateManager.current_class_renamed.connect(%ClassSelector.select_class)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%ClassSelector.include_subclasses_toggled.connect(%VREStateManager.set_include_subclasses)

	%ResourceList.row_clicked.connect(%VREStateManager.select)
	%ResourceList.prev_page_requested.connect(%VREStateManager.prev_page)
	%ResourceList.next_page_requested.connect(%VREStateManager.next_page)

	%Toolbar.refresh_requested.connect(%VREStateManager.refresh_resource_list_values)
	%Toolbar.error_occurred.connect(error_dialog.show_error)

	%VREStateManager.selection_changed.connect(_on_selection_changed)
	%VREStateManager.pagination_changed.connect(%ResourceList.update_pagination_bar)

	%BulkEditor.error_occurred.connect(error_dialog.show_error)
	%BulkEditor.resources_edited.connect(_on_resources_edited)

	%ClassSelector.set_classes(%VREStateManager.project_resource_classes)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


# ── Class selector ─────────────────────────────────────────────────────────────

func _on_class_selected(class_name_str: String) -> void:
	%VREStateManager.set_class(class_name_str)
	%BulkEditor.current_class_name = class_name_str
	%BulkEditor.current_class_script = %VREStateManager.current_class_script
	%BulkEditor.current_class_property_list = %VREStateManager.current_class_property_list
	%BulkEditor.subclasses_property_lists = %VREStateManager.subclasses_property_lists
	%Toolbar.set_class_info(class_name_str, %VREStateManager.global_class_map)


func _on_project_classes_changed(classes: Array[String]) -> void:
	%ClassSelector.set_classes(classes)


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[ResourceProperty]) -> void:
	%ResourceList.set_data(resources, columns)


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_selection_changed(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources
	%ResourceList.update_selection(resources)
	%Toolbar.update_selection(resources)


func _on_resources_edited(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		%ResourceList.refresh_row(res.resource_path)


func _on_close_requested() -> void:
	queue_free()
