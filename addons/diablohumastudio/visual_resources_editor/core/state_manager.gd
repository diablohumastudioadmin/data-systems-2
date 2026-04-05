@tool
class_name VREStateManager
extends RefCounted

var _model: VREModel = VREModel.new()
var model: VREModel:
	get: return _model

# ── Signals (public API — unchanged) ──────────────────────────────────────────
signal resources_replaced(resources: Array[Resource], current_shared_property_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)
signal resources_edited(resources: Array[Resource])
signal error_occurred(message: String)
signal delete_selected_requested(selected_resources_paths: Array[String])
signal create_new_resource_requested()

# ── Public read-only accessors (same API as before) ───────────────────────────
var current_class_name: String:
	get: return _model.session.selected_class

var selected_resources: Array[Resource]:
	get: return _model.session.selected_resources

var _selected_paths: Array[String]:
	get:
		var paths: Array[String] = []
		for res: Resource in _model.session.selected_resources:
			paths.append(res.resource_path)
		return paths

var global_class_map: Array[Dictionary]:
	get: return _model.global_class_map

var global_class_name_list: Array[String]:
	get: return _model.global_class_name_list

var global_class_to_path_map: Dictionary[String, String]:
	get: return _model.global_class_to_path_map

var current_class_resources: Array[Resource]:
	get: return _model.current_class_resources

var current_class_script: GDScript:
	get: return _model.current_class_script

var current_class_property_list: Array[ResourceProperty]:
	get: return _model.current_class_property_list

var current_included_class_property_lists: Dictionary:
	get: return _model.current_included_class_property_lists

var current_shared_property_list: Array[ResourceProperty]:
	get: return _model.current_shared_property_list

func start() -> void:
	if not Engine.is_editor_hint(): return
	
	_model.resources_replaced.connect(resources_replaced.emit)
	_model.resources_added.connect(resources_added.emit)
	_model.resources_modified.connect(resources_modified.emit)
	_model.resources_removed.connect(resources_removed.emit)
	_model.project_classes_changed.connect(project_classes_changed.emit)
	_model.selection_changed.connect(selection_changed.emit)
	_model.pagination_changed.connect(pagination_changed.emit)
	_model.current_class_renamed.connect(current_class_renamed.emit)
	_model.resources_edited.connect(resources_edited.emit)
	_model.error_occurred.connect(error_occurred.emit)
	_model.delete_selected_requested.connect(delete_selected_requested.emit)
	_model.create_new_resource_requested.connect(create_new_resource_requested.emit)
	
	_model.start()


func stop() -> void:
	if not Engine.is_editor_hint(): return
	_model.stop()


# ── Public API (unchanged) ─────────────────────────────────────────────────────

func set_current_class(class_name_str: String) -> void:
	_model.session.selected_class = class_name_str


func set_include_subclasses(value: bool) -> void:
	_model.session.include_subclasses = value


func notify_resources_edited(resources: Array[Resource]) -> void:
	_model.notify_resources_edited(resources)


func request_delete_selected_resources(resource_paths: Array[String]) -> void:
	_model.request_delete_selected_resources(resource_paths)


func request_create_new_resouce() -> void:
	_model.request_create_new_resouce()


func report_error(message: String) -> void:
	_model.report_error(message)


func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	_model.set_selected_resources(resource, ctrl_held, shift_held)


func next_page() -> void:
	_model.next_page()


func prev_page() -> void:
	_model.prev_page()


func refresh_resource_list_values() -> void:
	_model.refresh_resource_list_values()
