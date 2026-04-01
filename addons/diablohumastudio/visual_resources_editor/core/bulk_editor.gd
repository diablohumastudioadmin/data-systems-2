@tool
class_name BulkEditor
extends Node

const MAX_SAVE_ERROR_PATHS: int = 3

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()

var _inspector: EditorInspector
var _bulk_proxy: Resource = null


func _ready() -> void:
	_inspector = EditorInterface.get_inspector()
	if not _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.connect(_on_inspector_property_edited)
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	state_manager.selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	_clear_bulk_proxy()
	if _inspector and _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.disconnect(_on_inspector_property_edited)


func _clear_bulk_proxy() -> void:
	_bulk_proxy = null
	EditorInterface.inspect_object(null)


func _on_selection_changed(_resources: Array[Resource]) -> void:
	_create_bulk_proxy()


func _create_bulk_proxy() -> void:
	_clear_bulk_proxy()
	if state_manager.selected_resources.is_empty():
		return
	var script: GDScript = _get_common_script()
	if script == null:
		return
	_bulk_proxy = script.new()
	if state_manager.selected_resources.size() == 1:
		var res_class: String = script.get_global_name()
		var props: Array = state_manager.current_included_class_property_lists.get(
			res_class, state_manager.current_class_property_list)
		for prop: ResourceProperty in props:
			_bulk_proxy.set(prop.name, state_manager.selected_resources[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)


func _get_common_script() -> GDScript:
	var first_script: GDScript = state_manager.selected_resources[0].get_script()
	for i: int in state_manager.selected_resources.size():
		if state_manager.selected_resources[i].get_script() != first_script:
			return state_manager.current_class_script
	return first_script


func _on_inspector_property_edited(property: String) -> void:
	var edited_obj: Object = _inspector.get_edited_object()
	if not (_bulk_proxy and edited_obj == _bulk_proxy):
		return
	var new_value: Variant = _bulk_proxy.get(property)
	var saved: Array[Resource] = []
	var failed_paths: Array[String] = []
	for res: Resource in state_manager.selected_resources:
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
		state_manager.report_error(msg)
	if not saved.is_empty():
		state_manager.notify_resources_edited(saved)
