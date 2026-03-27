# VRE Architecture Proposal — Repository + Listener + Coordinator

## Problems

1. **`state_manager.gd` is ~450 lines** doing too many things: class maps, resource scanning, mtime diffing, selection, pagination, filesystem reactivity, property scanning, class rename detection, orphan resaving.
2. **Non-scene-tree testing is impossible** — everything depends on `EditorFileSystem`, `EditorInterface`, `ResourceLoader`, and scene-tree node references (`%DebounceTimer`). No way to inject test doubles.

## Design Decisions

1. **No debouncer** — Godot already coalesces multi-file operations into a single `filesystem_changed` / `script_classes_updated` call. The `DebounceTimer` is unnecessary. This lets every non-UI object be `RefCounted`.
2. **Two repositories** — `ClassesRepository` (class maps, properties) and `ResourcesRepository` (loaded `.tres` resources, mtime diffing). Separate concerns, separate test doubles.
3. **Dedicated `EditorFileSystemListener`** — One object connects to `EditorFileSystem`, owns the suppression logic (replacing `_classes_update_pending`), and emits clean signals. Repos never touch `EditorFileSystem` directly. This is the only Godot-editor-coupled piece outside UI.
4. **Children wire themselves** — Window receives state manager via `initialize()` and passes it down to each child. Each component connects its own signals in its own `initialize()`. Window only handles window-level concerns (status label, pagination bar, error dialog).

## Proposed Architecture

```
visual_resources_editor/
├── core/
│   ├── editor_filesystem_listener.gd     # Connects to EditorFileSystem, suppression, emits clean signals
│   ├── repositories/
│   │   ├── classes_repository.gd         # Abstract base (RefCounted)
│   │   ├── editor_classes_repository.gd  # Real impl — uses ProjectScanner
│   │   ├── resources_repository.gd       # Abstract base (RefCounted)
│   │   └── editor_resources_repository.gd# Real impl — uses ProjectScanner + mtime diffing
│   ├── state_manager.gd                  # Slim coordinator: selection, pagination, signal relay (~150 lines)
│   ├── project_scanner.gd               # Renamed from project_class_scanner (static utility, unchanged)
│   ├── bulk_editor.gd                   # Unchanged
│   └── data_models/
│       ├── resource_property.gd
│       └── class_definition.gd
├── ui/
│   ├── visual_resources_editor_window.gd/.tscn  # Passes state down, handles window-level UI only
│   ├── class_selector/                          # Wires itself via initialize(state)
│   ├── toolbar/                                 # Wires itself via initialize(state)
│   ├── resource_list/                           # Wires itself via initialize(state)
│   └── dialogs/                                 # Unchanged
├── visual_resources_editor_toolbar.gd           # Creates listener + repos + state, injects into window
└── visual_resources_editor_plugin.gd
```

### Layer Responsibilities

| Layer | Class | Owns | Depends On |
|---|---|---|---|
| **Infra** | `EditorFileSystemListener` | signal suppression, EditorFileSystem connection | `EditorFileSystem` (Godot API) |
| **Data** | `ClassesRepository` (abstract) | class maps, class list, property lists | nothing |
| **Data** | `ResourcesRepository` (abstract) | loaded resources, mtimes, incremental diff | nothing |
| **Coordination** | `VREStateManager` (RefCounted) | selection, pagination, page slicing, cross-repo coordination, UI signal emission | both repositories |
| **View** | Window + components | display, user interaction | `VREStateManager` (each child wires itself) |

### Signal Flow

```
EditorFileSystem
    │
    ▼
EditorFileSystemListener (suppression logic)
    ├── classes_changed ──→ EditorClassesRepository._on_classes_changed()
    │                           → rebuilds maps
    │                           → emits updated / class_list_changed
    │
    └── filesystem_changed ──→ EditorResourcesRepository._on_filesystem_changed()
                                  → mtime diff scan
                                  → emits resources_changed(added, removed, modified)

VREStateManager
    ├── listens to ClassesRepository.updated → tells listener to suppress next filesystem_changed
    ├── listens to ClassesRepository.class_list_changed → emits project_classes_changed, handles rename
    ├── listens to ResourcesRepository.resources_reset → page 0, emit resources_replaced
    └── listens to ResourcesRepository.resources_changed → page-filter, emit granular signals

Window.initialize(state)
    ├── %ClassSelector.initialize(state)   → connects class_selected, include_subclasses_toggled
    ├── %ResourceList.initialize(state)    → connects resources_replaced/added/removed/modified, selection_changed
    ├── %Toolbar.initialize(state)         → connects selection_changed, refresh_requested
    └── %BulkEditor.initialize(state)      → connects selection_changed
    └── window connects pagination_changed, status-label updates
```

---

## 1. EditorFileSystemListener

The only object that touches `EditorFileSystem`. Owns suppression logic. Everything else connects to its signals instead.

```gdscript
@tool
class_name EditorFileSystemListener
extends RefCounted

signal classes_changed()
signal filesystem_changed()

var _suppressed: bool = false


func start() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if not efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.connect(_on_script_classes_updated)
		if not efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.connect(_on_filesystem_changed)


func stop() -> void:
	var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.script_classes_updated.is_connected(_on_script_classes_updated):
			efs.script_classes_updated.disconnect(_on_script_classes_updated)
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)


func suppress_next_filesystem_changed() -> void:
	_suppressed = true


func _on_script_classes_updated() -> void:
	classes_changed.emit()


func _on_filesystem_changed() -> void:
	if _suppressed:
		_suppressed = false
		return
	filesystem_changed.emit()
```

**Why the listener owns suppression instead of state_manager doing it on repos:**
- Repos don't know about `EditorFileSystem` or each other — they just receive "something changed" signals
- The suppression is a filesystem-level concern (signal A always fires before signal B) — it belongs at the filesystem level
- State_manager tells the listener to suppress, not the repo. Clean separation.

---

## 2. ClassesRepository

### Abstract Base — `classes_repository.gd`

```gdscript
@tool
class_name ClassesRepository
extends RefCounted

signal updated()
signal class_list_changed(classes: Array[String])
signal property_list_changed()
signal orphaned_resources_found(resources: Array[Resource])

var global_class_map: Array[Dictionary] = []
var class_to_path_map: Dictionary[String, String] = {}
var class_to_parent_map: Dictionary[String, String] = {}
var class_name_list: Array[String] = []

var current_class_script: GDScript = null
var current_class_property_list: Array[ResourceProperty] = []
var included_class_property_lists: Dictionary = {}
var shared_property_list: Array[ResourceProperty] = []

# Virtual methods
func rebuild() -> void: pass
func get_class_script(class_name_str: String) -> GDScript: return null
func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]: return []
func scan_properties(base_class: String, included_classes: Array[String]) -> void: pass
```

### Real Impl — `editor_classes_repository.gd`

```gdscript
@tool
class_name EditorClassesRepository
extends ClassesRepository

func _init() -> void:
	_rebuild_maps()


func rebuild() -> void:
	var previous_classes: Array[String] = class_name_list.duplicate()
	_rebuild_maps()
	updated.emit()

	if previous_classes == class_name_list:
		_check_property_changes()
		return

	_handle_orphans(previous_classes)
	class_list_changed.emit(class_name_list)


func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]:
	if include_subclasses:
		return ProjectScanner.get_descendant_classes(base_class, class_to_parent_map)
	return [base_class]


func scan_properties(base_class: String, included_classes: Array[String]) -> void:
	var old_props: Array[ResourceProperty] = current_class_property_list.duplicate()
	current_class_script = get_class_script(base_class)
	included_class_property_lists = ProjectScanner.get_properties_from_script_names(included_classes)
	var empty_props: Array[ResourceProperty] = []
	current_class_property_list = included_class_property_lists.get(base_class, empty_props)
	shared_property_list = ProjectScanner.unite_classes_properties(included_classes, class_to_path_map)


func get_class_script(class_name_str: String) -> GDScript:
	var path: String = class_to_path_map.get(class_name_str, "")
	if not path.is_empty():
		return load(path)
	return null


func _rebuild_maps() -> void:
	global_class_map = ProjectScanner.build_global_classes_map()
	class_to_parent_map = ProjectScanner.build_project_classes_parent_map(global_class_map)
	class_to_path_map = ProjectScanner.build_class_to_path_map(global_class_map)
	class_name_list = ProjectScanner.get_project_resource_classes(global_class_map)


func _check_property_changes() -> void:
	# Compare current properties against stored — if different, emit property_list_changed
	# State manager decides what to do (rescan + re-emit page data)
	property_list_changed.emit()


func _handle_orphans(previous_classes: Array[String]) -> void:
	var removed_classes: Array[String] = []
	for cls: String in previous_classes:
		if not class_name_list.has(cls):
			removed_classes.append(cls)
	if removed_classes.is_empty():
		return
	var orphaned: Array[Resource] = ProjectScanner.load_classed_resources_from_dir(removed_classes)
	if not orphaned.is_empty():
		orphaned_resources_found.emit(orphaned)
```

### Test Double — `stub_classes_repository.gd` (in `tests/`)

```gdscript
class_name StubClassesRepository
extends ClassesRepository

# Setup:
#   repo.class_name_list = ["Weapon", "Armor"]
#   repo.class_to_path_map = {"Weapon": "res://...", "Armor": "res://..."}
#   repo.class_to_parent_map = {"Armor": "Resource", "Weapon": "Resource"}
#
# Trigger changes:
#   repo.class_name_list.append("Potion")
#   repo.class_list_changed.emit(repo.class_name_list)

func rebuild() -> void:
	updated.emit()

func resolve_included_classes(base_class: String, include_subclasses: bool) -> Array[String]:
	if not include_subclasses:
		return [base_class]
	# Simple stub: walk class_to_parent_map like the real one
	var result: Array[String] = [base_class]
	for cls: String in class_to_parent_map:
		if class_to_parent_map[cls] == base_class:
			result.append(cls)
	return result

func scan_properties(_base_class: String, _included_classes: Array[String]) -> void:
	pass  # test pre-populates shared_property_list, included_class_property_lists
```

---

## 3. ResourcesRepository

### Abstract Base — `resources_repository.gd`

```gdscript
@tool
class_name ResourcesRepository
extends RefCounted

signal resources_reset(resources: Array[Resource])
signal resources_changed(
	added: Array[Resource],
	removed: Array[Resource],
	modified: Array[Resource]
)

var resources: Array[Resource] = []

# Virtual
func load_resources(class_names: Array[String]) -> void: pass
func scan_for_changes() -> void: pass
```

No `suppress_next_scan()` — suppression lives in `EditorFileSystemListener`.
No `start_listening()` / `stop_listening()` — repos don't touch `EditorFileSystem`.

### Real Impl — `editor_resources_repository.gd`

```gdscript
@tool
class_name EditorResourcesRepository
extends ResourcesRepository

var _current_class_names: Array[String] = []
var _mtimes: Dictionary[String, int] = {}


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

	# Detect new and modified
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

	# Detect deleted
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


func _rebuild_mtimes() -> void:
	_mtimes.clear()
	for res: Resource in resources:
		_mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)
```

### Test Double — `stub_resources_repository.gd` (in `tests/`)

```gdscript
class_name StubResourcesRepository
extends ResourcesRepository

# Setup:
#   repo.resources = [res1, res2, res3]
#
# Trigger:
#   repo.load_resources(["Weapon"])  → emits resources_reset
#   repo.resources_changed.emit([new], [deleted], [modified])  → manual

func load_resources(_class_names: Array[String]) -> void:
	resources_reset.emit(resources)

func scan_for_changes() -> void:
	pass  # tests emit resources_changed manually
```

---

## 4. VREStateManager (RefCounted, ~150 lines)

Pure coordination. No `EditorFileSystem`, no `ResourceLoader`, no scene tree.

```gdscript
@tool
class_name VREStateManager
extends RefCounted

signal resources_replaced(resources: Array[Resource], property_list: Array[ResourceProperty])
signal resources_added(resources: Array[Resource])
signal resources_modified(resources: Array[Resource])
signal resources_removed(resources: Array[Resource])
signal project_classes_changed(classes: Array[String])
signal selection_changed(resources: Array[Resource])
signal pagination_changed(page: int, page_count: int)
signal current_class_renamed(new_name: String)

const PAGE_SIZE: int = 50

var classes_repo: ClassesRepository
var resources_repo: ResourcesRepository
var _listener: EditorFileSystemListener  # null in tests

var _current_class_name: String = ""
var _include_subclasses: bool = true
var _current_included_class_names: Array[String] = []

# Selection
var selected_resources: Array[Resource] = []
var _selected_paths: Array[String] = []
var _selected_resources_last_index: int = -1

# Pagination
var _current_page: int = 0
var _current_page_resources: Array[Resource] = []


func _init(
		p_classes_repo: ClassesRepository,
		p_resources_repo: ResourcesRepository,
		p_listener: EditorFileSystemListener = null) -> void:
	classes_repo = p_classes_repo
	resources_repo = p_resources_repo
	_listener = p_listener

	classes_repo.updated.connect(_on_classes_updated)
	classes_repo.class_list_changed.connect(_on_class_list_changed)
	classes_repo.property_list_changed.connect(_on_property_list_changed)
	classes_repo.orphaned_resources_found.connect(_on_orphaned_resources_found)
	resources_repo.resources_reset.connect(_on_resources_reset)
	resources_repo.resources_changed.connect(_on_resources_changed)

	if _listener:
		_listener.classes_changed.connect(classes_repo.rebuild)
		_listener.filesystem_changed.connect(_on_filesystem_changed)


# ── Public API ───────────────────────────────────────────────────────────────

func set_current_class(class_name_str: String) -> void:
	_current_class_name = class_name_str
	_resolve_and_load()


func set_include_subclasses(value: bool) -> void:
	_include_subclasses = value
	_resolve_and_load()


func refresh() -> void:
	_resolve_and_load()


# ── Selection ────────────────────────────────────────────────────────────────

func set_selected_resources(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
	var all_resources: Array[Resource] = resources_repo.resources
	var current_idx: int = all_resources.find(resource)
	if shift_held and _selected_resources_last_index != -1 and current_idx != -1:
		_handle_select_shift(current_idx, all_resources)
	elif ctrl_held:
		_handle_select_ctrl(resource, current_idx)
	else:
		_handle_select_no_key(resource, current_idx)
	selection_changed.emit(selected_resources.duplicate())


func _handle_select_shift(current_idx: int, all_resources: Array[Resource]) -> void:
	selected_resources.clear()
	_selected_paths.clear()
	var from: int = mini(_selected_resources_last_index, current_idx)
	var to: int = maxi(_selected_resources_last_index, current_idx)
	for i: int in (to - from + 1):
		var res: Resource = all_resources[from + i]
		selected_resources.append(res)
		_selected_paths.append(res.resource_path)


func _handle_select_ctrl(resource: Resource, current_idx: int) -> void:
	if selected_resources.has(resource):
		selected_resources.erase(resource)
		_selected_paths.erase(resource.resource_path)
	else:
		selected_resources.append(resource)
		_selected_paths.append(resource.resource_path)
	_selected_resources_last_index = current_idx


func _handle_select_no_key(resource: Resource, current_idx: int) -> void:
	selected_resources.clear()
	_selected_paths.clear()
	selected_resources.append(resource)
	_selected_paths.append(resource.resource_path)
	_selected_resources_last_index = current_idx


# ── Pagination ───────────────────────────────────────────────────────────────

func next_page() -> void:
	if _current_page < _page_count() - 1:
		_set_current_page(_current_page + 1)


func prev_page() -> void:
	if _current_page > 0:
		_set_current_page(_current_page - 1)


func _set_current_page(page: int) -> void:
	_current_page = clampi(page, 0, _page_count() - 1)
	_slice_page()
	pagination_changed.emit(_current_page, _page_count())


func _page_count() -> int:
	if resources_repo.resources.is_empty():
		return 1
	return ceili(float(resources_repo.resources.size()) / float(PAGE_SIZE))


func _slice_page() -> void:
	var start: int = _current_page * PAGE_SIZE
	var end: int = mini(start + PAGE_SIZE, resources_repo.resources.size())
	_current_page_resources = resources_repo.resources.slice(start, end)


# ── Private — repo signal handlers ──────────────────────────────────────────

func _resolve_and_load() -> void:
	if _current_class_name.is_empty():
		return
	_current_included_class_names = classes_repo.resolve_included_classes(
		_current_class_name, _include_subclasses)
	classes_repo.scan_properties(_current_class_name, _current_included_class_names)
	resources_repo.load_resources(_current_included_class_names)
	# resources_repo emits resources_reset → _on_resources_reset


func _on_classes_updated() -> void:
	# script_classes_updated always fires before filesystem_changed.
	# Suppress the upcoming filesystem_changed to avoid double-scan.
	if _listener:
		_listener.suppress_next_filesystem_changed()


func _on_class_list_changed(classes: Array[String]) -> void:
	project_classes_changed.emit(classes)
	if _current_class_name.is_empty():
		return
	if not classes.has(_current_class_name):
		var new_name: String = _detect_class_rename()
		if new_name.is_empty():
			_clear_view()
			return
		_current_class_name = new_name
		current_class_renamed.emit(new_name)
	_resolve_and_load()


func _on_property_list_changed() -> void:
	if _current_class_name.is_empty():
		return
	classes_repo.scan_properties(_current_class_name, _current_included_class_names)
	# Resave resources so they pick up new property defaults
	for res: Resource in resources_repo.resources:
		ResourceSaver.save(res, res.resource_path)
	_restore_selection()
	_slice_page()
	resources_replaced.emit(_current_page_resources, classes_repo.shared_property_list)
	pagination_changed.emit(_current_page, _page_count())


func _on_orphaned_resources_found(orphaned: Array[Resource]) -> void:
	for res: Resource in orphaned:
		ResourceSaver.save(res, res.resource_path)


func _on_filesystem_changed() -> void:
	if _current_class_name.is_empty():
		return
	resources_repo.scan_for_changes()
	# resources_repo emits resources_changed → _on_resources_changed


func _on_resources_reset(_resources: Array[Resource]) -> void:
	_current_page = 0
	_restore_selection()
	_slice_page()
	resources_replaced.emit(_current_page_resources, classes_repo.shared_property_list)
	pagination_changed.emit(_current_page, _page_count())


func _on_resources_changed(
		added: Array[Resource], removed: Array[Resource], modified: Array[Resource]) -> void:
	_restore_selection()
	_slice_page()

	var page_added: Array[Resource] = _page_filter(added)
	var page_removed: Array[Resource] = _page_filter(removed)
	var page_modified: Array[Resource] = _page_filter(modified)

	if not page_removed.is_empty():
		resources_removed.emit(page_removed)
	if not page_added.is_empty():
		resources_added.emit(page_added)
	if not page_modified.is_empty():
		resources_modified.emit(page_modified)
	pagination_changed.emit(_current_page, _page_count())


func _page_filter(res_list: Array[Resource]) -> Array[Resource]:
	var page_paths: Dictionary[String, bool] = {}
	for res: Resource in _current_page_resources:
		page_paths[res.resource_path] = true
	var filtered: Array[Resource] = []
	for res: Resource in res_list:
		if page_paths.has(res.resource_path):
			filtered.append(res)
	return filtered


func _restore_selection() -> void:
	var prev_paths: Array[String] = _selected_paths.duplicate()
	selected_resources.clear()
	_selected_paths.clear()
	for res: Resource in resources_repo.resources:
		if prev_paths.has(res.resource_path):
			selected_resources.append(res)
			_selected_paths.append(res.resource_path)
	_selected_resources_last_index = resources_repo.resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
	selection_changed.emit(selected_resources.duplicate())


func _detect_class_rename() -> String:
	if classes_repo.current_class_script == null:
		return ""
	var old_path: String = classes_repo.current_class_script.resource_path
	if old_path.is_empty():
		return ""
	for cls: String in classes_repo.class_to_path_map:
		if classes_repo.class_to_path_map[cls] == old_path:
			return cls
	return ""


func _clear_view() -> void:
	_current_class_name = ""
	_current_included_class_names.clear()
	selected_resources.clear()
	_selected_paths.clear()
	_selected_resources_last_index = -1
	_current_page = 0
	_current_page_resources.clear()
	var empty_resources: Array[Resource] = []
	var empty_props: Array[ResourceProperty] = []
	resources_replaced.emit(empty_resources, empty_props)
	selection_changed.emit(empty_resources)
	pagination_changed.emit(0, 1)
```

---

## 5. Wiring — Plugin Toolbar

```gdscript
# visual_resources_editor_toolbar.gd

var _listener: EditorFileSystemListener
var _classes_repo: ClassesRepository
var _resources_repo: ResourcesRepository
var _state: VREStateManager

func open_visual_editor_window():
	if is_instance_valid(visual_resources_editor_window):
		visual_resources_editor_window.grab_focus()
		return

	# 1. Create infrastructure
	_listener = EditorFileSystemListener.new()
	_classes_repo = EditorClassesRepository.new()
	_resources_repo = EditorResourcesRepository.new()

	# 2. Create state manager — wires itself to repos + listener in _init()
	_state = VREStateManager.new(_classes_repo, _resources_repo, _listener)

	# 3. Create window, inject state — window passes state to children
	visual_resources_editor_window = VISUAL_RESOURCES_EDITOR_WINDOW_SCENE.instantiate()
	EditorInterface.get_base_control().add_child(visual_resources_editor_window)
	visual_resources_editor_window.initialize(_state)

	# 4. Start listening AFTER everything is wired
	_listener.start()

	visual_resources_editor_window.close_requested.connect(func():
		_listener.stop()
		visual_resources_editor_window = null
	)
	visual_resources_editor_window.popup_centered()
```

---

## 6. Window — Passes State Down, Handles Window-Level Only

```gdscript
# visual_resources_editor_window.gd

var _state: VREStateManager
var error_dialog: ErrorDialog
var _visible_count: int = 0


func initialize(state: VREStateManager) -> void:
	_state = state
	error_dialog = ErrorDialog.new()
	error_dialog.name = "ErrorDialog"
	add_child(error_dialog)

	# Pass state to children — they wire themselves
	%ClassSelector.initialize(state)
	%ResourceList.initialize(state)
	%Toolbar.initialize(state)
	%BulkEditor.initialize(state)

	# Window-level connections only
	state.pagination_changed.connect(_on_pagination_changed)
	state.resources_replaced.connect(_on_resources_replaced_status)
	state.resources_added.connect(_on_resources_changed_status)
	state.resources_removed.connect(_on_resources_changed_status)
	state.selection_changed.connect(_on_selection_changed_status)

	%PrevBtn.pressed.connect(state.prev_page)
	%NextBtn.pressed.connect(state.next_page)
	%BulkEditor.error_occurred.connect(error_dialog.show_error)

	%ClassSelector.set_classes(state.classes_repo.class_name_list)


func _on_pagination_changed(page: int, page_count: int) -> void:
	%PaginationBar.visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1


func _on_resources_replaced_status(resources: Array[Resource], _props: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	_update_status("%d resource(s)" % _visible_count)


func _on_resources_changed_status(_resources: Array[Resource]) -> void:
	_visible_count = %ResourceList.get_row_count()
	if _state.selected_resources.is_empty():
		_update_status("%d resource(s)" % _visible_count)


func _on_selection_changed_status(resources: Array[Resource]) -> void:
	if resources.size() > 0:
		_update_status("%d selected" % resources.size())
	else:
		_update_status("%d resource(s)" % _visible_count)


func _update_status(text: String) -> void:
	%StatusLabel.text = text
```

### Children Wire Themselves — Examples

```gdscript
# class_selector.gd
func initialize(state: VREStateManager) -> void:
	class_selected.connect(state.set_current_class)
	include_subclasses_toggled.connect(state.set_include_subclasses)
	state.project_classes_changed.connect(set_classes)
	state.current_class_renamed.connect(select_class)


# resource_list.gd
func initialize(state: VREStateManager) -> void:
	state.resources_replaced.connect(replace_resources)
	state.resources_added.connect(add_resources)
	state.resources_removed.connect(remove_resources)
	state.resources_modified.connect(modify_resources)
	state.selection_changed.connect(update_selection)
	row_clicked.connect(state.set_selected_resources)


# toolbar.gd
func initialize(state: VREStateManager) -> void:
	refresh_requested.connect(state.refresh)
	state.selection_changed.connect(update_selection)


# bulk_editor.gd
func initialize(state: VREStateManager) -> void:
	state.selection_changed.connect(func(resources: Array[Resource]):
		edited_resources = resources
	)
	# class info for proxy creation
	state.resources_replaced.connect(func(_res: Array[Resource], _props: Array[ResourceProperty]):
		current_class_name = state._current_class_name
		current_class_script = state.classes_repo.current_class_script
		current_class_property_list = state.classes_repo.current_class_property_list
		current_included_class_property_lists = state.classes_repo.included_class_property_lists
	)
```

---

## 7. Suppression Flow (Replaces `_classes_update_pending`)

```
1. Godot fires script_classes_updated
2. EditorFileSystemListener._on_script_classes_updated()
   → emits classes_changed

3. VREStateManager receives classes_changed (via listener → classes_repo.rebuild)
   → classes_repo.rebuild() runs, emits updated
   → VREStateManager._on_classes_updated()
     → calls _listener.suppress_next_filesystem_changed()
     → _listener._suppressed = true

4. Godot fires filesystem_changed (always follows script_classes_updated)
5. EditorFileSystemListener._on_filesystem_changed()
   → sees _suppressed == true
   → resets _suppressed = false
   → does NOT emit filesystem_changed
   → resources_repo never hears about it — no double scan
```

**Testability**: In tests, there's no listener. You emit repo signals manually. The suppression logic is only relevant in the real editor, and it's tested by testing `EditorFileSystemListener` in isolation (call `suppress_next_filesystem_changed()`, then `_on_filesystem_changed()`, verify signal not emitted).

---

## 8. Migration Phases — Each Phase is Testable

### Phase 1 — Foundations (testable immediately)

**Create**: `EditorFileSystemListener`, abstract bases (`ClassesRepository`, `ResourcesRepository`), test doubles (`StubClassesRepository`, `StubResourcesRepository`). Rename `ProjectClassScanner` → `ProjectScanner`.

**Don't touch**: `state_manager.gd`, window, or any UI.

**Tests**:
- `EditorFileSystemListener`: suppression logic — call `suppress_next_filesystem_changed()`, call `_on_filesystem_changed()`, assert `filesystem_changed` signal NOT emitted. Call `_on_filesystem_changed()` without suppression, assert signal IS emitted.
- `StubClassesRepository`: verify signals emit, `resolve_included_classes` returns expected results with pre-populated data.
- `StubResourcesRepository`: verify `load_resources` emits `resources_reset`.

**Plugin state**: old `state_manager.gd` still runs everything. New files exist but aren't used yet. Plugin works unchanged.

---

### Phase 2 — Extract ClassesRepository (testable)

**Create**: `EditorClassesRepository` with real logic moved from `state_manager.gd`.

**Modify**: `state_manager.gd` — receives `ClassesRepository` in constructor, delegates class map rebuilding, property scanning, class rename detection. Remove: `_set_maps()`, `_handle_global_classes_updated()`, `_resave_orphaned_resources()`, `_handle_property_changes()`, `_get_current_class_props()`, `_get_class_script()`, `_scan_current_properties()`, `_resolve_current_classes()`.

**state_manager still**: extends Node, owns resources, selection, pagination, `EditorFileSystem` connection for `filesystem_changed`.

**Tests** (using `StubClassesRepository`):
- State manager class rename detection: pre-populate stub with class script, remove class from list, emit `class_list_changed` → assert `current_class_renamed` emitted with correct name.
- State manager property change: emit `property_list_changed` → assert `resources_replaced` emitted.
- State manager class list change: emit `class_list_changed` → assert `project_classes_changed` relayed.

**Plugin state**: Plugin works. State manager is smaller (~300 lines). Classes repo handles class-related logic.

---

### Phase 3 — Extract ResourcesRepository (testable)

**Create**: `EditorResourcesRepository` with real logic moved from `state_manager.gd`.

**Modify**: `state_manager.gd` — receives `ResourcesRepository` in constructor, delegates resource loading and mtime scanning. Remove: `set_current_class_resources()`, `_scan_class_resources_for_changes()`, `_rebuild_current_class_resource_mtimes()`, `current_class_resources`, `_current_class_resources_mtimes`.

**state_manager still**: extends Node (temporarily), owns selection, pagination, page-level slicing. Still connects to `EditorFileSystem.filesystem_changed` directly.

**Tests** (using both stubs):
- Full reset flow: `state.set_current_class("Weapon")` → stub emits `resources_reset` → assert `resources_replaced` emitted with correct page slice.
- Incremental changes: emit `resources_changed([new], [], [])` → assert `resources_added` emitted (filtered to current page).
- Pagination: load 120 resources into stub, assert page count = 3, call `next_page()`, assert correct slice.
- Selection: load resources, call `set_selected_resources()` with shift/ctrl, assert correct selection state.
- Suppress coordination: emit `classes_repo.updated` → assert `listener.suppress_next_filesystem_changed()` called.

**Plugin state**: Plugin works. State manager is now ~150 lines. Both repos handle their domains.

---

### Phase 4 — StateManager to RefCounted + Listener Integration (testable)

**Modify**: `state_manager.gd` — change `extends Node` → `extends RefCounted`. Add `EditorFileSystemListener` parameter to `_init()`. Remove direct `EditorFileSystem` connections. Wire listener signals in `_init()`.

**Modify**: `visual_resources_editor_toolbar.gd` — create listener, repos, state manager. Inject into window via `initialize()`.

**Modify**: `state_manager.tscn` — delete (no longer needed).

**Tests** (same as Phase 3, all still pass because stubs are already RefCounted):
- All previous tests continue to work — no listener needed in tests (`null` is valid).
- New test: create state with `StubClassesRepository` + `StubResourcesRepository` + no listener, verify full signal flow works end-to-end.

**Plugin state**: Plugin works. State manager is RefCounted. Listener handles all EditorFileSystem coupling.

---

### Phase 5 — Children Wire Themselves (manual test in editor)

**Modify**: `visual_resources_editor_window.gd` — replace `connect_components()` with `initialize(state)` that passes state to children.

**Modify**: `class_selector.gd`, `resource_list.gd`, `toolbar.gd`, `bulk_editor.gd` — each gets `initialize(state: VREStateManager)` method, wires its own signals.

**Remove**: `connect_components()` from window.

**Tests**: Manual in-editor testing. This phase is pure UI wiring reshuffling — no logic changes. Each component's `initialize()` is a small, readable method.

**Plugin state**: Plugin works. Architecture is complete.

---

## 9. What Changes for UI Components

Only Phase 5 touches UI components, and the change is minimal: each component gains an `initialize(state)` method where it connects its own signals. The signal names, payloads, and behavior are identical. No visual changes, no new scenes, no layout changes.

---

## 10. Summary

| Before | After |
|---|---|
| `state_manager.gd`: ~450 lines, does everything | ~150 lines: selection, pagination, coordination |
| Untestable (EditorFileSystem, scene tree) | All core logic testable with stub repos, no scene tree |
| `_classes_update_pending` implicit flag in state_manager | `EditorFileSystemListener.suppress_next_filesystem_changed()` — explicit, isolated, testable |
| Repos don't exist — all scanning in state_manager | `ClassesRepository` owns class maps + properties, `ResourcesRepository` owns resources + mtime diffing |
| Window is a giant switchboard connecting all signals | Window passes state down, each child wires itself |
| Debounce timer node required | No debouncer needed — Godot coalesces filesystem events |
| Everything coupled to EditorFileSystem | Only `EditorFileSystemListener` touches EditorFileSystem |
