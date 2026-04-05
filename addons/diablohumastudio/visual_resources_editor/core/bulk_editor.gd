@tool
class_name BulkEditor
extends Node

const MAX_SAVE_ERROR_PATHS: int = 3

var model: VREModel = null:
	set(value):
		model = value
		if is_node_ready():
			_connect_model()

var _inspector: EditorInspector
var _bulk_proxy: Resource = null
var _inspected_selection_paths: Array[String] = []


func _ready() -> void:
	_inspector = EditorInterface.get_inspector()
	if not _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.connect(_on_inspector_property_edited)
	if model:
		_connect_model()


func _connect_model() -> void:
	model.selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	_clear_bulk_proxy()
	if _inspector and _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.disconnect(_on_inspector_property_edited)


func _clear_bulk_proxy() -> void:
	_bulk_proxy = null
	_inspected_selection_paths.clear()
	EditorInterface.inspect_object(null)


func _on_selection_changed(resources: Array[Resource]) -> void:
	var current_selection_paths: Array[String] = _get_selection_paths(resources)
	var edited_obj: Object = _inspector.get_edited_object()
	if _bulk_proxy and edited_obj == _bulk_proxy and current_selection_paths == _inspected_selection_paths:
		return
	_create_bulk_proxy()


func _create_bulk_proxy() -> void:
	_clear_bulk_proxy()
	if model.session.selected_resources.is_empty():
		return
	var script: GDScript = _get_common_script()
	if script == null:
		return
	_bulk_proxy = script.new()
	if model.session.selected_resources.size() == 1:
		var res_class: String = script.get_global_name()
		var empty_props: Array[ResourceProperty] = []
		var fallback: Array[ResourceProperty] = model.current_class_property_list \
			if not model.current_class_property_list.is_empty() else empty_props
		var props: Array[ResourceProperty] = model.current_included_class_property_lists.get(
			res_class, fallback)
		for prop: ResourceProperty in props:
			_bulk_proxy.set(prop.name, model.session.selected_resources[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)
	_inspected_selection_paths = _get_selection_paths(model.session.selected_resources)


func _get_selection_paths(resources: Array[Resource]) -> Array[String]:
	var paths: Array[String] = []
	for res: Resource in resources:
		paths.append(res.resource_path)
	return paths


func _get_common_script() -> GDScript:
	var first_script: GDScript = model.session.selected_resources[0].get_script()
	for i: int in model.session.selected_resources.size():
		if model.session.selected_resources[i].get_script() != first_script:
			return model.current_class_script
	return first_script


func _on_inspector_property_edited(property: String) -> void:
	var edited_obj: Object = _inspector.get_edited_object()
	if not (_bulk_proxy and edited_obj == _bulk_proxy):
		return
	var new_value: Variant = _bulk_proxy.get(property)
	var saved: Array[Resource] = []
	var failed_paths: Array[String] = []
	for res: Resource in model.session.selected_resources:
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
		model.report_error(msg)
	if not saved.is_empty():
		model.notify_resources_edited(saved)
