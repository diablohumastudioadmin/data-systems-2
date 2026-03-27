@tool
class_name VisualResourcesEditorWindow
extends Window

var _state: VREStateManager
var error_dialog: ErrorDialog
var _visible_count: int = 0


func create_and_add_dialogs() -> void:
	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)


func initialize(state: VREStateManager) -> void:
	_state = state

	state.resources_replaced.connect(_on_state_resources_replaced)
	state.resources_added.connect(_on_state_resources_added)
	state.resources_modified.connect(_on_state_resources_modified)
	state.resources_removed.connect(_on_state_resources_removed)
	state.project_classes_changed.connect(_on_project_classes_changed)
	state.current_class_renamed.connect(%ClassSelector.select_class)

	%ClassSelector.class_selected.connect(_on_class_selected)
	%ClassSelector.include_subclasses_toggled.connect(state.set_include_subclasses)

	%ResourceList.row_clicked.connect(state.set_selected_resources)

	%PrevBtn.pressed.connect(state.prev_page)
	%NextBtn.pressed.connect(state.next_page)

	%Toolbar.refresh_requested.connect(state.refresh_resource_list_values)
	%Toolbar.error_occurred.connect(error_dialog.show_error)

	state.selection_changed.connect(_on_selection_changed)
	state.pagination_changed.connect(_on_pagination_changed)

	%BulkEditor.error_occurred.connect(error_dialog.show_error)
	%BulkEditor.resources_edited.connect(_on_resources_edited)

	%ClassSelector.set_classes(state.classes_repo.class_name_list)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


# ── Class selector ─────────────────────────────────────────────────────────────

func _on_class_selected(class_name_str: String) -> void:
	_state.set_current_class(class_name_str)
	%BulkEditor.current_class_name = class_name_str
	%BulkEditor.current_class_script = _state.classes_repo.current_class_script
	%BulkEditor.current_class_property_list = _state.classes_repo.current_class_property_list
	%BulkEditor.current_included_class_property_lists = _state.classes_repo.included_class_property_lists
	%Toolbar.set_class_info(class_name_str, _state.classes_repo.global_class_map)


func _on_project_classes_changed(classes: Array[String]) -> void:
	%ClassSelector.set_classes(classes)


# ── State → UI ─────────────────────────────────────────────────────────────────

func _on_state_resources_replaced(
			resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	%ResourceList.replace_resources(resources, current_shared_propery_list)
	_update_status("%d resource(s)" % _visible_count)


func _on_state_resources_added(resources: Array[Resource]) -> void:
	%ResourceList.add_resources(resources)
	%ResourceList.update_selection(_state.selected_resources)
	_visible_count = %ResourceList.get_row_count()
	if _state.selected_resources.is_empty():
		_update_status("%d resource(s)" % _visible_count)


func _on_state_resources_modified(resources: Array[Resource]) -> void:
	%ResourceList.modify_resources(resources)
	%ResourceList.update_selection(_state.selected_resources)


func _on_state_resources_removed(resources: Array[Resource]) -> void:
	%ResourceList.remove_resources(resources)
	%ResourceList.update_selection(_state.selected_resources)
	_visible_count = %ResourceList.get_row_count()
	if _state.selected_resources.is_empty():
		_update_status("%d resource(s)" % _visible_count)


# ── Selection & inspection ─────────────────────────────────────────────────────

func _on_selection_changed(resources: Array[Resource]) -> void:
	%BulkEditor.edited_resources = resources
	%ResourceList.update_selection(resources)
	%Toolbar.update_selection(resources)
	var count: int = resources.size()
	if count > 0:
		_update_status("%d selected" % count)
	else:
		_update_status("%d resource(s)" % _visible_count)


func _on_resources_edited(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		%ResourceList.refresh_row(res.resource_path)


# ── Pagination ────────────────────────────────────────────────────────────────

func _on_pagination_changed(page: int, page_count: int) -> void:
	%PaginationBar.visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1


# ── Status ────────────────────────────────────────────────────────────────────

func _update_status(text: String) -> void:
	%StatusLabel.text = text


func _on_close_requested() -> void:
	queue_free()
