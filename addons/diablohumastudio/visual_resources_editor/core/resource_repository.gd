@tool
class_name ResourceRepository
extends RefCounted

## Emitted after a full reload (class change, subclass toggle, refresh).
## UI should rebuild entirely on this.
signal resources_reset(resources: Array[Resource])

## Emitted after an incremental filesystem scan finds changes.
## UI should add/remove/update only the affected rows.
signal resources_delta(
	added: Array[Resource],
	removed: Array[Resource],
	modified: Array[Resource]
)

var current_class_resources: Array[Resource] = []
var _mtimes: Dictionary[String, int] = {}


## Full reload for the given class names. Sorts by path. Always emits resources_reset.
func load_resources(class_names: Array[String]) -> void:
	current_class_resources = ProjectClassScanner.load_classed_resources_from_dir(class_names)
	current_class_resources.sort_custom(
		func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_mtimes()
	resources_reset.emit(current_class_resources.duplicate())


## Incremental scan: compares current filesystem state against the cached mtimes.
## Emits resources_delta only if something changed; silent otherwise.
func scan_for_changes(class_names: Array[String]) -> void:
	var updated: Array[Resource] = current_class_resources.duplicate()
	var current_paths: Array[String] = ProjectClassScanner.scan_folder_for_classed_tres_paths(class_names)
	var added: Array[Resource] = []
	var removed: Array[Resource] = []
	var modified: Array[Resource] = []

	for path: String in current_paths:
		var mtime: int = FileAccess.get_modified_time(path)
		if not _mtimes.has(path):
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				updated.append(res)
				added.append(res)
		elif mtime != _mtimes[path]:
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				for i: int in updated.size():
					if updated[i].resource_path == path:
						updated[i] = res
						break
				modified.append(res)

	var known_paths: Array = _mtimes.keys()
	for path: String in known_paths:
		if not current_paths.has(path):
			for i: int in updated.size():
				if updated[i].resource_path == path:
					removed.append(updated[i])
					updated.remove_at(i)
					break

	if added.is_empty() and removed.is_empty() and modified.is_empty():
		return

	current_class_resources = updated
	current_class_resources.sort_custom(
		func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_mtimes()
	resources_delta.emit(added, removed, modified)


## Resaves all current resources (used on property schema change).
func resave_all() -> void:
	for res: Resource in current_class_resources:
		ResourceSaver.save(res, res.resource_path)


## Resaves a specific subset (used for orphaned class cleanup).
func resave_resources(resources: Array[Resource]) -> void:
	for res: Resource in resources:
		ResourceSaver.save(res, res.resource_path)


## Returns the resource_path of each currently loaded resource.
func get_paths() -> Array[String]:
	var paths: Array[String] = []
	for res: Resource in current_class_resources:
		paths.append(res.resource_path)
	return paths


func clear() -> void:
	current_class_resources.clear()
	_mtimes.clear()


func _rebuild_mtimes() -> void:
	_mtimes.clear()
	for res: Resource in current_class_resources:
		_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)
