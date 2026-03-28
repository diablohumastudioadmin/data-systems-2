@tool
class_name BulkEditor
extends Node

signal error_occurred(message: String)
signal resources_edited(resources: Array[Resource])

const MAX_SAVE_ERROR_PATHS: int = 3

var current_class_name: String = ""
var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var current_included_class_property_lists: Dictionary = {}
var edited_resources : Array[Resource] = [] :
	set(new_value):
		edited_resources = new_value
		_create_bulk_proxy()
var _inspector: EditorInspector
var _bulk_proxy: Resource = null


func initialize(state: VREStateManager) -> void:
	resources_edited.connect(state.notify_resources_edited)
	state.selection_changed.connect(func(resources: Array[Resource]) -> void:
		edited_resources = resources
	)
	state.resources_replaced.connect(func(_resources: Array[Resource], _props: Array[ResourceProperty]) -> void:
		current_class_name = state._current_class_name
		current_class_script = state.classes_repo.current_class_script
		current_class_property_list = state.classes_repo.current_class_property_list
		current_included_class_property_lists = state.classes_repo.included_class_property_lists
	)


func _ready() -> void:
	_inspector = EditorInterface.get_inspector()
	if not _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.connect(_on_inspector_property_edited)


func _exit_tree() -> void:
	_clear_bulk_proxy()
	if _inspector and _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.disconnect(_on_inspector_property_edited)


func _clear_bulk_proxy() -> void:
	_bulk_proxy = null
	EditorInterface.inspect_object(null)


func _create_bulk_proxy() -> void:
	_clear_bulk_proxy()
	if edited_resources.is_empty():
		return
	var script: GDScript = _get_common_script()
	if script == null:
		return
	_bulk_proxy = script.new()
	if edited_resources.size() == 1:
		var res_class: String = script.get_global_name()
		var props: Array = current_included_class_property_lists.get(res_class, current_class_property_list)
		for prop: ResourceProperty in props:
			_bulk_proxy.set(prop.name, edited_resources[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)


func _get_common_script() -> GDScript:
	var first_script: GDScript = edited_resources[0].get_script()
	for i: int in edited_resources.size():
		if edited_resources[i].get_script() != first_script:
			return current_class_script
	return first_script


func _on_inspector_property_edited(property: String) -> void:
	var edited_obj: Object = _inspector.get_edited_object()

	if _bulk_proxy and edited_obj == _bulk_proxy:
		var new_value: Variant = _bulk_proxy.get(property)
		var saved: Array[Resource] = []
		var failed_paths: Array[String] = []
		for res: Resource in edited_resources:
			if property not in res: continue
			res.set(property, new_value)
			var err: Error = ResourceSaver.save(res, res.resource_path)
			if err != OK:
				failed_paths.append(res.resource_path)
			else:
				saved.append(res)
		if not failed_paths.is_empty():
			var shown: Array[String] = failed_paths.slice(0, MAX_SAVE_ERROR_PATHS)
			var msg: String = "Failed to save:\n%s" % "\n".join(shown)
			if failed_paths.size() > MAX_SAVE_ERROR_PATHS:
				msg += "\n... and %d more" % (failed_paths.size() - MAX_SAVE_ERROR_PATHS)
			error_occurred.emit(msg)
		if not saved.is_empty():
			resources_edited.emit(saved)
		EditorInterface.get_resource_filesystem().scan_sources()
		return
