@tool
class_name SelectionManager
extends RefCounted

signal selection_changed(resources: Array[Resource])

var selected_resources: Array[Resource] = []
var _last_index: int = -1


## Main entry point — routes to the correct select mode based on held keys.
## all_resources: the full ordered list used to resolve shift-range indices.
func set_selected(
	resource: Resource, ctrl_held: bool, shift_held: bool,
	all_resources: Array[Resource]
) -> void:
	var current_idx: int = all_resources.find(resource)
	if shift_held and _last_index != -1 and current_idx != -1:
		_select_range(current_idx, all_resources)
	elif ctrl_held:
		_toggle(resource, current_idx)
	else:
		_select_single(resource, current_idx)
	selection_changed.emit(selected_resources.duplicate())


## Re-matches previously selected paths against a new resource list.
## Call this after any load or scan that changes the resource array identity.
func restore(all_resources: Array[Resource]) -> void:
	var prev_paths: Array[String] = get_paths()
	selected_resources.clear()
	var restored_paths: Array[String] = []
	for res: Resource in all_resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			restored_paths.append(res.resource_path)
	_last_index = (
		all_resources.find(selected_resources.back())
		if not selected_resources.is_empty()
		else -1
	)
	if prev_paths == restored_paths:
		return
	selection_changed.emit(selected_resources.duplicate())


func clear() -> void:
	selected_resources.clear()
	_last_index = -1
	selection_changed.emit(selected_resources.duplicate())


## Returns the resource_path of every currently selected resource.
func get_paths() -> Array[String]:
	var paths: Array[String] = []
	for res: Resource in selected_resources:
		paths.append(res.resource_path)
	return paths


func _select_range(current_idx: int, all_resources: Array[Resource]) -> void:
	selected_resources.clear()
	var from: int = mini(_last_index, current_idx)
	var to: int = maxi(_last_index, current_idx)
	for i: int in (to - from + 1):
		selected_resources.append(all_resources[from + i])
	# Anchor stays unchanged on shift+click


func _toggle(resource: Resource, current_idx: int) -> void:
	if selected_resources.has(resource):
		selected_resources.erase(resource)
	else:
		selected_resources.append(resource)
	_last_index = current_idx


func _select_single(resource: Resource, current_idx: int) -> void:
	selected_resources.clear()
	selected_resources.append(resource)
	_last_index = current_idx
