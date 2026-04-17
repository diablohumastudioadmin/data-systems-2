@tool
class_name BulkEditor
extends Node

var session: SessionStateModel = null:
	set(value):
		session = value
		if is_node_ready():
			_connect_dependencies()

var resource_repo: ResourceRepository = null:
	set(value):
		resource_repo = value
		if is_node_ready():
			_connect_dependencies()

var class_registry: ClassRegistry = null:
	set(value):
		class_registry = value
		if is_node_ready():
			_connect_dependencies()

var _inspector: EditorInspector
var _bulk_proxy: Resource = null
var _inspected_selection_paths: Array[String] = []
var _connected: bool = false


func _ready() -> void:
	_inspector = EditorInterface.get_inspector()
	if not _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.connect(_on_inspector_property_edited)
	_connect_dependencies()


func _connect_dependencies() -> void:
	if _connected:
		return
	if session == null or resource_repo == null or class_registry == null:
		return
	session.selected_paths_changed.connect(_on_selection_changed)
	resource_repo.resources_saved.connect(_on_resources_saved)
	_connected = true


func _exit_tree() -> void:
	_clear_bulk_proxy()
	if _inspector and _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.disconnect(_on_inspector_property_edited)


func _clear_bulk_proxy() -> void:
	_bulk_proxy = null
	_inspected_selection_paths.clear()
	EditorInterface.inspect_object(null)


func _on_selection_changed(paths: Array[String]) -> void:
	var edited_obj: Object = _inspector.get_edited_object()
	if _bulk_proxy and edited_obj == _bulk_proxy and paths == _inspected_selection_paths:
		return
	_create_bulk_proxy()


func _create_bulk_proxy() -> void:
	_clear_bulk_proxy()
	var selected: Array[Resource] = _resolve_selected_resources()
	if selected.is_empty():
		return
	var script: GDScript = _get_common_script(selected)
	if script == null:
		return
	_bulk_proxy = script.new()
	if selected.size() == 1:
		var script_name: String = script.get_global_name()
		var props: Array[ResourceProperty] = class_registry.get_properties(script_name)
		if props.is_empty():
			props = class_registry.get_properties(session.selected_class)
		for prop: ResourceProperty in props:
			_bulk_proxy.set(prop.name, selected[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)
	_inspected_selection_paths = session.selected_paths.duplicate()


func _resolve_selected_resources() -> Array[Resource]:
	var result: Array[Resource] = []
	var lookup: Dictionary = {}
	for res: Resource in resource_repo.current_class_resources:
		lookup[res.resource_path] = res
	for path: String in session.selected_paths:
		if lookup.has(path):
			result.append(lookup[path])
	return result


func _get_common_script(selected: Array[Resource]) -> GDScript:
	var first_script: GDScript = selected[0].get_script()
	for i: int in selected.size():
		if selected[i].get_script() != first_script:
			return class_registry.get_class_script(session.selected_class)
	return first_script


func _on_resources_saved(_paths: Array[String]) -> void:
	# ResourceListVM listens directly to repo.resources_saved; keep proxy stable here.
	if _bulk_proxy:
		_inspected_selection_paths = session.selected_paths.duplicate()


func _on_inspector_property_edited(property: String) -> void:
	var edited_obj: Object = _inspector.get_edited_object()
	if not (_bulk_proxy and edited_obj == _bulk_proxy):
		return
	var new_value: Variant = _bulk_proxy.get(property)
	var entries: Array[Dictionary] = []
	for res: Resource in _resolve_selected_resources():
		if property not in res:
			continue
		res.set(property, new_value)
		entries.append({"path": res.resource_path, "resource": res})
	resource_repo.save_multi(entries)
