@tool
class_name EditorResourcesRepository
extends IResourcesRepository

var _current_class_names: Array[String] = []
var _mtimes: Dictionary[String, int] = {}

func _init(p_listener: EditorFileSystemListener) -> void:
	listener = p_listener
	listener.filesystem_changed.connect(_on_listener_filesystem_changed)


func load_resources(class_names: Array[String]) -> void:
	_current_class_names = class_names
	resources = ProjectScanner.load_classed_resources_from_dir(_current_class_names)
	resources.sort_custom(func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_mtimes()
	resources_reset.emit(resources)


func scan_for_changes() -> void:
	if _current_class_names.is_empty():
		return

	var current_paths: Array[String] = ProjectScanner.scan_folder_for_classed_tres_paths(_current_class_names)
	var added: Array[Resource] = []
	var removed: Array[Resource] = []
	var modified: Array[Resource] = []
	var changed: bool = false

	# Detect new and modified resources
	for path: String in current_paths:
		var mtime: int = FileAccess.get_modified_time(path)
		if not _mtimes.has(path):
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				added.append(res)
				resources.append(res)
				changed = true
		elif mtime != _mtimes[path]:
			var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if res:
				modified.append(res)
				for i: int in resources.size():
					if resources[i].resource_path == path:
						resources[i] = res
						break
				changed = true

	# Detect deleted resources
	var known_paths: Array = _mtimes.keys()
	for path: String in known_paths:
		if not current_paths.has(path):
			for i: int in resources.size():
				if resources[i].resource_path == path:
					removed.append(resources[i])
					resources.remove_at(i)
					break
			changed = true

	if not changed:
		return

	resources.sort_custom(func(a: Resource, b: Resource) -> bool: return a.resource_path < b.resource_path)
	_rebuild_mtimes()
	resources_changed.emit(added, removed, modified)


# ── Private ────────────────────────────────────────────────────────────────────

func _on_listener_filesystem_changed() -> void:
	#TODO check for current clas name null
	scan_for_changes()

func _rebuild_mtimes() -> void:
	_mtimes.clear()
	for res: Resource in resources:
		_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)
