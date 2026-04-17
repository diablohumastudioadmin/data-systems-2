@tool
class_name VisualResourcesEditorWindow
extends Window

var _session: SessionStateModel
var _class_registry: ClassRegistry
var _resource_repo: ResourceRepository
var _fs_listener: EditorFileSystemListener

var _toolbar_vm: ToolbarVM
var _resource_list_vm: ResourceListVM


func _ready() -> void:
	_session = SessionStateModel.new()
	_class_registry = ClassRegistry.new()
	_resource_repo = ResourceRepository.new()
	_fs_listener = EditorFileSystemListener.new()

	_class_registry.classes_changed.connect(_on_classes_changed)
	_fs_listener.filesystem_changed.connect(_on_filesystem_changed)
	_fs_listener.script_classes_updated.connect(_on_script_classes_updated)

	_toolbar_vm = ToolbarVM.new(_session)
	_resource_list_vm = ResourceListVM.new(_session, _resource_repo, _class_registry)
	_toolbar_vm.refresh_requested.connect(_resource_list_vm.refresh_current_view)

	var confirm_delete_vm: ConfirmDeleteDialogVM = ConfirmDeleteDialogVM.new(_resource_repo, _toolbar_vm)
	confirm_delete_vm.bind_resource_list(_resource_list_vm)

	%ClassSelector.vm = ClassSelectorVM.new(_session, _class_registry)
	%SubclassFilter.vm = SubclassFilterVM.new(_session)
	%Toolbar.vm = _toolbar_vm
	%Dialogs.save_dialog_vm = SaveResourceDialogVM.new(
		_session, _class_registry, _resource_repo, _toolbar_vm)
	%Dialogs.confirm_delete_vm = confirm_delete_vm
	%Dialogs.error_dialog_vm = ErrorDialogVM.new(_resource_repo)
	%ResourceList.vm = _resource_list_vm
	%BulkEditor.session = _session
	%BulkEditor.resource_repo = _resource_repo
	%BulkEditor.class_registry = _class_registry

	_fs_listener.start()
	_class_registry.rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()


func _on_close_requested() -> void:
	_fs_listener.stop()
	queue_free()


func _on_classes_changed(previous: Array[String], current: Array[String]) -> void:
	_resource_repo.on_classes_changed(previous, current, _session.selected_class, _class_registry)


func _on_script_classes_updated() -> void:
	var list_changed: bool = _class_registry.rebuild()
	if list_changed:
		return
	var current_classes: Array[String] = _class_registry.global_class_name_list
	var schema_resaved: bool = _resource_repo.on_classes_changed(
		current_classes, current_classes, _session.selected_class, _class_registry)
	if schema_resaved:
		_resource_list_vm.refresh_current_view()


func _on_filesystem_changed() -> void:
	if _session.selected_class.is_empty():
		return
	var included_class_names: Array[String] = _class_registry.get_included_classes(
		_session.selected_class, _session.include_subclasses)
	_resource_repo.scan_for_changes(included_class_names)
