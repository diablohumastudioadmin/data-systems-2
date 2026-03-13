@tool
class_name BulkEditor
extends Node

var current_class_name: String
var edited_resources : Array[Resource] = [] :
	set(new_value):
		edited_resources = new_value
		_create_bulk_proxy()
var _inspector: EditorInspector = EditorInterface.get_inspector()
var _bulk_proxy: Resource = null

func _ready() -> void:
	if not _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.connect(_on_inspector_property_edited)


func _exit_tree() -> void:
	if _inspector.property_edited.is_connected(_on_inspector_property_edited):
		_inspector.property_edited.disconnect(_on_inspector_property_edited)


func _create_bulk_proxy():
	if edited_resources.is_empty():
		return
	var script: GDScript = edited_resources[0].get_script() \
		if edited_resources.size() == 1 else _get_current_class_script()
	if script == null:
		return
	_bulk_proxy = script.new()
	for prop: Dictionary in script.get_script_property_list():
		_bulk_proxy.set(prop.name, edited_resources[0].get(prop.name))
	EditorInterface.inspect_object(_bulk_proxy)


func _get_current_class_script() -> GDScript:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == current_class_name:
			return load(entry.get("path", ""))
	return null


func _on_inspector_property_edited(property: String) -> void:
	var edited_obj: Object = _inspector.get_edited_object()

	if _bulk_proxy and edited_obj == _bulk_proxy:
		var new_value: Variant = _bulk_proxy.get(property)
		for res: Resource in edited_resources:
			res.set(property, new_value)
			ResourceSaver.save(res, res.resource_path)
			%ResourceList.refresh_row(res.resource_path)
		return
