@tool
class_name VisualResourcesEditorWindow
extends Window

var save_resource_dialog: SaveResourceDialog
var error_dialog: ErrorDialog
var confirm_delete_dialog: ComfirmDeleteDialog

func create_and_add_dialogs() -> void:
	save_resource_dialog = SaveResourceDialog.new()
	save_resource_dialog.name = "SaveResourceDialog"
	add_child(save_resource_dialog)

	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)

	confirm_delete_dialog = ComfirmDeleteDialog.new()
	confirm_delete_dialog.name = "ConfirmDeleteDialog"
	add_child(confirm_delete_dialog)


func connect_components() -> void:
	%VREStateManager.data_changed.connect(_on_state_data_changed)
	%VREStateManager.project_classes_changed.connect(_on_project_classes_changed)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

	%ResourceList.row_clicked.connect(%VREStateManager.select)
	%ResourceList.prev_page_requested.connect(%VREStateManager.prev_page)
	%ResourceList.next_page_requested.connect(%VREStateManager.next_page)
	%ResourceList.create_requested.connect(save_resource_dialog.show_create_dialog)
	%ResourceList.delete_requested.connect(confirm_delete_dialog.show_delete_dialog)
	%ResourceList.refresh_requested.connect(%VREStateManager.rescan)

	%VREStateManager.selection_changed.connect(_on_selection_changed)
	%VREStateManager.pagination_changed.connect(%ResourceList.update_pagination_bar)

	save_resource_dialog.error_occurred.connect(error_dialog.show_error)
	confirm_delete_dialog.error_occurred.connect(error_dialog.show_error)
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
	save_resource_dialog.current_class_name = class_name_str
	save_resource_dialog.global_classes_map = %VREStateManager.global_classes_map


func _on_include_subclasses_toggled(pressed: bool) -> void:
	%VREStateManager.set_include_subclasses(pressed)
	%SubclassWarningLabel.visible = pressed


func _on_project_classes_changed(classes: Array[String]) -> void:
	%ClassSelector.set_classes(classes)


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_data_changed(
		resources: Array[Resource], columns: Array[Dictionary]) -> void:
	%ResourceList.set_data(resources, columns)


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_selection_changed(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources
	%ResourceList.update_selection(resources)


func _on_resources_edited(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		%ResourceList.refresh_row(res.resource_path)


func _on_close_requested() -> void:
	queue_free()
