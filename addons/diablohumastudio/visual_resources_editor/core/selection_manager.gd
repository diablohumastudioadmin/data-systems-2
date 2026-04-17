@tool
class_name SelectionManager
extends RefCounted

signal selection_changed(paths: Array[String])

var selected_paths: Array[String] = []
var _last_index: int = -1


## Main entry point — routes to the correct select mode based on held keys.
## all_paths: the full ordered list of resource paths used to resolve shift-range indices.
func set_selected(
	path: String, ctrl_held: bool, shift_held: bool,
	all_paths: Array[String]
) -> void:
	var current_idx: int = all_paths.find(path)
	if shift_held and _last_index != -1 and current_idx != -1:
		_select_range(current_idx, all_paths)
	elif ctrl_held:
		_toggle(path, current_idx)
	else:
		_select_single(path, current_idx)
	selection_changed.emit(selected_paths.duplicate())


func clear() -> void:
	selected_paths.clear()
	_last_index = -1
	selection_changed.emit(selected_paths.duplicate())


func _select_range(current_idx: int, all_paths: Array[String]) -> void:
	selected_paths.clear()
	var from: int = mini(_last_index, current_idx)
	var to: int = maxi(_last_index, current_idx)
	for i: int in (to - from + 1):
		selected_paths.append(all_paths[from + i])
	# Anchor stays unchanged on shift+click


func _toggle(path: String, current_idx: int) -> void:
	if selected_paths.has(path):
		selected_paths.erase(path)
	else:
		selected_paths.append(path)
	_last_index = current_idx


func _select_single(path: String, current_idx: int) -> void:
	selected_paths.clear()
	selected_paths.append(path)
	_last_index = current_idx
