@tool
class_name DH_VRE_PaginationManager
extends RefCounted

## Emitted when the class/filter changes and the page must fully rebuild.
signal page_replaced(resources: Array[Resource])

## Emitted when page navigation causes rows to appear or disappear.
signal page_delta(
	added: Array[Resource],
	removed: Array[Resource],
	modified: Array[Resource]
)

signal pagination_changed(page: int, page_count: int)

const PAGE_SIZE: int = 50

var current_page_resources: Array[Resource] = []
var _page: int = 0
var _page_mtimes: Dictionary[String, int] = {}


## Hard reset to page 0. Emits page_replaced + pagination_changed.
## Call after DH_VRE_ResourceRepository.load_resources().
func reset(all_resources: Array[Resource]) -> void:
	_page = 0
	current_page_resources = _slice(all_resources)
	_rebuild_page_mtimes()
	page_replaced.emit(current_page_resources.duplicate())
	pagination_changed.emit(_page, _page_count(all_resources.size()))


## Navigate to a specific page. Emits page_delta + pagination_changed.
func set_page(page: int, all_resources: Array[Resource]) -> void:
	var previous_resources: Array[Resource] = current_page_resources.duplicate()
	var previous_mtimes: Dictionary[String, int] = _page_mtimes.duplicate()
	_page = clampi(page, 0, _page_count(all_resources.size()) - 1)
	current_page_resources = _slice(all_resources)
	_rebuild_page_mtimes()
	_emit_delta(previous_resources, previous_mtimes)
	pagination_changed.emit(_page, _page_count(all_resources.size()))


func next(all_resources: Array[Resource]) -> void:
	if _page < _page_count(all_resources.size()) - 1:
		set_page(_page + 1, all_resources)


func prev(all_resources: Array[Resource]) -> void:
	if _page > 0:
		set_page(_page - 1, all_resources)


## Re-slices the current page without emitting any delta signals.
## Used when property schema changes require a full resources_replaced
## but the page index should not change and no per-row delta is needed.
func refresh_silent(all_resources: Array[Resource]) -> void:
	current_page_resources = _slice(all_resources)
	_rebuild_page_mtimes()


func current_page() -> int:
	return _page


func page_count(total: int) -> int:
	return _page_count(total)


func _slice(all_resources: Array[Resource]) -> Array[Resource]:
	var start: int = _page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, all_resources.size())
	return all_resources.slice(start, end)


func _page_count(total: int) -> int:
	if total == 0:
		return 1
	return ceili(float(total) / float(PAGE_SIZE))


func _rebuild_page_mtimes() -> void:
	_page_mtimes.clear()
	for res: Resource in current_page_resources:
		_page_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)


func _emit_delta(
	previous_resources: Array[Resource],
	previous_mtimes: Dictionary[String, int]
) -> void:
	var prev_map: Dictionary[String, Resource] = {}
	for res: Resource in previous_resources:
		prev_map[res.resource_path] = res

	var curr_map: Dictionary[String, Resource] = {}
	for res: Resource in current_page_resources:
		curr_map[res.resource_path] = res

	var removed: Array[Resource] = []
	for path: String in prev_map:
		if not curr_map.has(path):
			removed.append(prev_map[path])

	var added: Array[Resource] = []
	for path: String in curr_map:
		if not prev_map.has(path):
			added.append(curr_map[path])

	var modified: Array[Resource] = []
	for path: String in curr_map:
		if not prev_map.has(path):
			continue
		if previous_mtimes.get(path, -1) != _page_mtimes.get(path, -1):
			modified.append(curr_map[path])

	if not added.is_empty() or not removed.is_empty() or not modified.is_empty():
		page_delta.emit(added, removed, modified)
