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

## Emitted when a disk operation fails. Listener shows the error UI.
signal error_occurred(message: String)

## Emitted after one or more resources are saved successfully.
signal resources_saved(paths: Array[String])

signal selected_class_changed(class_name_: String)
signal include_subclasses_changed(include: bool)
signal confirmation_needed(paths: Array[String])

const MAX_ERROR_PATHS: int = 3

var class_registry: ClassRegistry

var selected_class: String = "":
	set(value):
		if selected_class != value:
			selected_class = value
			selected_class_changed.emit(value)
			_reload()

var include_subclasses: bool = true:
	set(value):
		if include_subclasses != value:
			include_subclasses = value
			include_subclasses_changed.emit(value)
			_reload()

var current_class_resources: Array[Resource] = []
var _mtimes: Dictionary[String, int] = {}
var _last_known_props: Array[ResourceProperty] = []
var _fs_listener: EditorFileSystemListener


func _init(p_class_registry: ClassRegistry = null) -> void:
	class_registry = p_class_registry if p_class_registry else ClassRegistry.new()
	_fs_listener = EditorFileSystemListener.new()
	class_registry.classes_changed.connect(_on_classes_changed)
	_fs_listener.script_classes_updated.connect(_on_script_classes_updated)
	_fs_listener.filesystem_changed.connect(_on_filesystem_changed)


func start() -> void:
	_fs_listener.start()
	class_registry.rebuild()


func stop() -> void:
	_fs_listener.stop()


func reload() -> void:
	_reload()


## Full reload for the given class names. Always emits resources_reset.
func load_resources(class_names: Array[String]) -> void:
	current_class_resources = ProjectClassScanner.load_classed_resources_from_dir(class_names)
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


## Looks up a loaded resource by path. Falls back to ResourceLoader.load
## if the path isn't in current_class_resources.
func get_by_path(path: String) -> Resource:
	for res: Resource in current_class_resources:
		if res.resource_path == path:
			return res
	return ResourceLoader.load(path)


## Instantiates a resource from `script` and saves it at `path`.
## Emits error_occurred on failure.
func create(script: GDScript, path: String) -> Error:
	if script == null:
		error_occurred.emit("Script is null; cannot create resource.")
		return ERR_INVALID_PARAMETER
	if not script.can_instantiate():
		var class_name_: String = script.get_global_name()
		error_occurred.emit("Can't instantiate %s.\nCheck its constructor." % class_name_)
		return ERR_CANT_CREATE
	var instance: Resource = script.new()
	var err: Error = ResourceSaver.save(instance, path)
	if err != OK:
		error_occurred.emit("Failed to save resource:\n%s" % path)
	return err


## Emits confirmation_needed so the confirm dialog can gate the deletion.
func request_delete(paths: Array[String]) -> void:
	if paths.is_empty():
		return
	confirmation_needed.emit(paths)


## Moves the given resource paths to trash and refreshes EditorFileSystem.
## Emits error_occurred for paths that failed; silent on success.
func delete(paths: Array[String]) -> void:
	var failed_paths: Array[String] = []
	for path: String in paths:
		if not path.begins_with("res://"):
			push_warning("VRE: Skipping delete of path outside project: %s" % path)
			failed_paths.append(path)
			continue
		var err: Error = OS.move_to_trash(ProjectSettings.globalize_path(path))
		if err != OK:
			failed_paths.append(path)
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	for path: String in paths:
		efs.update_file(path)
	if not failed_paths.is_empty():
		error_occurred.emit("Failed to delete:\n%s" % "\n".join(failed_paths))


## Saves a single resource to disk. Emits resources_saved on success,
## error_occurred on failure.
func save_one(path: String, resource: Resource) -> Error:
	var err: Error = ResourceSaver.save(resource, path)
	if err != OK:
		error_occurred.emit("Failed to save resource:\n%s" % path)
		return err
	resources_saved.emit([path] as Array[String])
	return OK


## Batch-saves resources. `entries` is an Array of {path: String, resource: Resource}.
## Emits resources_saved with the successful paths; emits error_occurred with
## the first MAX_ERROR_PATHS failures on any failure.
func save_multi(entries: Array[Dictionary]) -> void:
	var saved_paths: Array[String] = []
	var failed_paths: Array[String] = []
	for entry: Dictionary in entries:
		var path: String = entry["path"]
		var resource: Resource = entry["resource"]
		var err: Error = ResourceSaver.save(resource, path)
		if err == OK:
			saved_paths.append(path)
		else:
			failed_paths.append(path)
	if not saved_paths.is_empty():
		resources_saved.emit(saved_paths)
	if not failed_paths.is_empty():
		var shown: Array[String] = failed_paths.slice(0, MAX_ERROR_PATHS)
		var msg: String = "Failed to save:\n%s" % "\n".join(shown)
		if failed_paths.size() > MAX_ERROR_PATHS:
			msg += "\n... and %d more" % (failed_paths.size() - MAX_ERROR_PATHS)
		error_occurred.emit(msg)


## Returns the resource_path of each currently loaded resource.
func get_paths() -> Array[String]:
	var paths: Array[String] = []
	for res: Resource in current_class_resources:
		paths.append(res.resource_path)
	return paths


func clear() -> void:
	current_class_resources.clear()
	_mtimes.clear()


func _reload() -> void:
	if selected_class.is_empty():
		current_class_resources.clear()
		_mtimes.clear()
		resources_reset.emit([])
		return
	_last_known_props = class_registry.get_properties(selected_class).duplicate()
	var included: Array[String] = class_registry.get_included_classes(selected_class, include_subclasses)
	load_resources(included)


func _on_script_classes_updated() -> void:
	var list_changed: bool = class_registry.rebuild()
	if list_changed:
		return
	if selected_class.is_empty() or not class_registry.global_class_name_list.has(selected_class):
		return
	var new_props: Array[ResourceProperty] = class_registry.get_properties(selected_class)
	if ResourceProperty.arrays_equal(new_props, _last_known_props):
		return
	resave_all()
	resources_reset.emit(current_class_resources.duplicate())


func _on_classes_changed(previous: Array[String], current: Array[String]) -> void:
	_resave_orphaned(previous, current)
	if selected_class.is_empty() or not current.has(selected_class):
		return
	var new_props: Array[ResourceProperty] = class_registry.get_properties(selected_class)
	if ResourceProperty.arrays_equal(new_props, _last_known_props):
		return
	resave_all()
	resources_reset.emit(current_class_resources.duplicate())


func _on_filesystem_changed() -> void:
	if selected_class.is_empty():
		return
	var included: Array[String] = class_registry.get_included_classes(selected_class, include_subclasses)
	scan_for_changes(included)


func _resave_orphaned(previous: Array[String], current: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous:
		if not current.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned: Array[Resource] = ProjectClassScanner.load_classed_resources_from_dir(removed_classes)
	resave_resources(orphaned)


func _rebuild_mtimes() -> void:
	_mtimes.clear()
	for res: Resource in current_class_resources:
		_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)
