@tool
class_name SelectionManager
extends RefCounted

signal selection_changed(paths: Array[String])

var selected_paths: Array[String] = []
var _anchor_path: String = ""


## Main entry point — routes to the correct select mode based on held keys.
## all_paths: the full ordered list of resource paths used to resolve shift-range indices.
func set_selected(
	path: String, ctrl_held: bool, shift_held: bool,
	all_paths: Array[String]
) -> void:
	var current_idx: int = all_paths.find(path)
	var anchor_idx: int = all_paths.find(_anchor_path)
	if shift_held and anchor_idx != -1 and current_idx != -1:
		_select_range(current_idx, all_paths)
	elif ctrl_held:
		_toggle(path, current_idx)
	else:
		_select_single(path, current_idx)
	selection_changed.emit(selected_paths.duplicate())


func clear() -> void:
	selected_paths.clear()
	_anchor_path = ""
	selection_changed.emit(selected_paths.duplicate())


## Removes any selected paths that no longer exist in the current ordered list.
## Keeps the anchor stable when possible so shift-click still works after inserts.
func reconcile(all_paths: Array[String]) -> void:
	var valid_paths: Dictionary[String, bool] = {}
	for path: String in all_paths:
		valid_paths[path] = true

	var filtered: Array[String] = []
	for path: String in selected_paths:
		if valid_paths.has(path):
			filtered.append(path)

	var changed: bool = filtered != selected_paths
	selected_paths = filtered

	if not _anchor_path.is_empty() and not valid_paths.has(_anchor_path):
		_anchor_path = selected_paths[selected_paths.size() - 1] \
			if not selected_paths.is_empty() else ""

	if changed:
		selection_changed.emit(selected_paths.duplicate())


func _select_range(current_idx: int, all_paths: Array[String]) -> void:
	var anchor_idx: int = all_paths.find(_anchor_path)
	if anchor_idx == -1:
		_select_single(all_paths[current_idx], current_idx)
		return
	selected_paths.clear()
	var from: int = mini(anchor_idx, current_idx)
	var to: int = maxi(anchor_idx, current_idx)
	for i: int in (to - from + 1):
		selected_paths.append(all_paths[from + i])
	# Anchor stays unchanged on shift+click


func _toggle(path: String, current_idx: int) -> void:
	if selected_paths.has(path):
		selected_paths.erase(path)
	else:
		selected_paths.append(path)
	_anchor_path = path if current_idx != -1 else ""


func _select_single(path: String, current_idx: int) -> void:
	selected_paths.clear()
	selected_paths.append(path)
	_anchor_path = path if current_idx != -1 else ""
