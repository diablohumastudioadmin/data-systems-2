# Visual Resources Editor — MVVM Proposal

## Why MVVM

The current architecture is "Window as god-orchestrator": the Window script wires every signal between every child, routes data manually, and holds implicit knowledge about what each component needs. This works at small scale but creates problems:

1. **Window grows with every feature** — adding a filter, a sort, or a status bar means more signal wiring in Window
2. **Business logic leaks into UI** — BulkEditor saves resources directly, dialogs call `EditorFileSystem.scan()`, ResourceList manages selection semantics
3. **Testing is impossible** — you can't unit-test state transitions without instantiating the full scene tree
4. **Shared state is implicit** — "current class", "selected resources", "columns" are scattered across StateManager, BulkEditor, ResourceList, and Window

MVVM solves this by introducing a **ViewModel** layer: plain GDScript objects (no Node) that hold all state and logic, exposing it to Views via signals. Views become thin — they read from the ViewModel and call methods on it. No View talks to another View.

---

## MVVM in GDScript — The Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                         MODEL                               │
│  Pure data + persistence. No UI knowledge.                  │
│  ProjectClassScanner (static), ResourceSaver, DirAccess,    │
│  EditorFileSystem, ProjectSettings                          │
└──────────────────────────┬──────────────────────────────────┘
                           │ called by
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                       VIEWMODEL                             │
│  Extends RefCounted (not Node). Holds ALL mutable state.    │
│  Exposes state via properties + signals.                    │
│  Contains ALL business logic (scan, save, delete, select).  │
│  No %NodeName, no UI types, no scene tree access.           │
└──────────────────────────┬──────────────────────────────────┘
                           │ observed by (signals)
                           │ called by (methods)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                          VIEW                               │
│  .tscn scenes + thin .gd scripts.                           │
│  Reads from ViewModel, renders UI, forwards user actions    │
│  to ViewModel methods. No business logic.                   │
│  Does NOT talk to other Views — only to its ViewModel.      │
└─────────────────────────────────────────────────────────────┘
```

**Key rules:**
- ViewModel is a `RefCounted` (or `Resource`), NOT a `Node`. It has no place in the scene tree. This makes it testable without Godot scenes.
- Views hold a reference to the ViewModel (`var vm: VREViewModel`). They connect to its signals in `_ready()`.
- Views NEVER modify ViewModel state directly — they call methods (`vm.select_class("Weapon")`).
- ViewModel NEVER references Views — it emits signals. Views decide how to render.
- Model layer is unchanged: `ProjectClassScanner` stays static, `ResourceSaver`/`DirAccess` stay as Godot APIs.

---

## Current vs MVVM — Architecture Comparison

### Current: Window-as-Orchestrator

```
                    ┌──────────────────────────┐
                    │   Window (orchestrator)   │
                    │   routes ALL signals      │
                    │   holds implicit state    │
                    └──┬───┬───┬───┬───┬───┬──┘
                       │   │   │   │   │   │
          ┌────────────┘   │   │   │   │   └────────────┐
          ▼                ▼   │   ▼   │                ▼
   ClassSelector    StateManager│ BulkEditor      SaveDialog
   (view+logic)    (state+scan) │ (edit+save)    (create+scan)
                       ▼       │
                  ResourceList  │
                 (view+select   │
                  +state)       │
                       ▼        │
                  ResourceRow   │
                  (view+input)  ▼
                          ConfirmDeleteDialog
                          (delete+scan)
```

**Problems visible in the diagram:**
- Window has 6+ direct connections — it's a routing hub
- StateManager, BulkEditor, and dialogs each do their own I/O
- Selection state lives in ResourceList but BulkEditor needs it
- "Current class" is set separately on StateManager, BulkEditor, and SaveResourceDialog

### Proposed: MVVM

```
┌─────────────────────────────────────────────────────────────────┐
│                        MODEL LAYER                              │
│                                                                 │
│  ProjectClassScanner     ResourceSaver      DirAccess           │
│  (static utility)        (Godot API)        (Godot API)         │
│  EditorFileSystem        ProjectSettings                        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                    called by  │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     VREViewModel                                │
│                  extends RefCounted                              │
│                                                                 │
│  ── State ──────────────────────────────────────                │
│  available_classes: Array[String]                                │
│  selected_class: String                                         │
│  include_subclasses: bool                                       │
│  columns: Array[Dictionary]                                     │
│  resources: Array[Resource]                                     │
│  selected_paths: Array[String]                                  │
│  bulk_proxy: Resource                                           │
│  error_message: String                                          │
│  status_text: String                                            │
│                                                                 │
│  ── Signals ────────────────────────────────────                │
│  state_changed()           ← any state mutation                 │
│  classes_changed()         ← available_classes updated          │
│  selection_changed()       ← selected_paths changed             │
│  error_raised(msg)         ← error to display                  │
│                                                                 │
│  ── Commands (called by Views) ─────────────────                │
│  select_class(name)                                             │
│  toggle_include_subclasses(value)                               │
│  select_resource(path, shift)                                   │
│  select_resource_range(from_path, to_path)                      │
│  create_resource(target_path)                                   │
│  delete_resources(paths)                                        │
│  apply_bulk_edit(property, value)                                │
│  rescan()                                                       │
│  request_filesystem_rescan()                                    │
│                                                                 │
│  ── Internal ───────────────────────────────────                │
│  _scan_resources()                                              │
│  _build_columns()                                               │
│  _build_bulk_proxy()                                            │
│  _get_class_script()                                            │
│  _check_classes_changed()                                       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
              observed + called │
           ┌───────────┬───────┴────────┬──────────────┐
           ▼           ▼                ▼              ▼
    ┌────────────┐ ┌──────────┐ ┌────────────┐ ┌───────────┐
    │ClassSelect │ │ Resource │ │  Dialogs   │ │  Window   │
    │   View     │ │ ListView │ │ (save/del/ │ │  (thin    │
    │            │ │          │ │  error)    │ │  shell)   │
    │ reads:     │ │ reads:   │ │            │ │           │
    │ avail_cls  │ │ resources│ │ reads:     │ │ owns vm   │
    │ sel_class  │ │ columns  │ │ error_msg  │ │ passes to │
    │            │ │ sel_paths│ │            │ │ children  │
    │ calls:     │ │          │ │ calls:     │ │           │
    │ vm.select_ │ │ calls:   │ │ vm.create_ │ │ connects  │
    │   class()  │ │ vm.select│ │ vm.delete_ │ │ fs_changed│
    │            │ │ _resource│ │ resources()│ │ to vm     │
    └────────────┘ └──────────┘ └────────────┘ └───────────┘
```

---

## The ViewModel — Detailed Design

### State (all in one place)

```gdscript
class_name VREViewModel
extends RefCounted

# ── Signals ───────────────────────────────────────────────────
signal state_changed()
signal classes_changed(added: Array[String], removed: Array[String])
signal selection_changed()
signal error_raised(message: String)

# ── Observable State ──────────────────────────────────────────
var available_classes: Array[String] = []
var selected_class: String = ""
var include_subclasses: bool = true
var resolved_class_names: Array[String] = []   # base + descendants
var columns: Array[Dictionary] = []
var resources: Array[Resource] = []
var selected_paths: Array[String] = []         # selection by path, not ref
var bulk_proxy: Resource = null
var status_text: String = ""

# ── Cached Maps (private) ────────────────────────────────────
var _global_classes_map: Array[Dictionary] = []
var _classes_parent_map: Dictionary[String, String] = {}
```

### Commands (public methods Views call)

```gdscript
func initialize() -> void:
    ## Called once from Window._ready(). Loads initial class list.
    _refresh_maps()
    available_classes = ProjectClassScanner.get_resource_classes_in_folder(
        _classes_parent_map)
    classes_changed.emit(available_classes, [])


func select_class(class_name_str: String) -> void:
    if class_name_str == selected_class: return
    selected_class = class_name_str
    _scan_and_notify()


func toggle_include_subclasses(value: bool) -> void:
    if value == include_subclasses: return
    include_subclasses = value
    _scan_and_notify()


func select_resource(path: String, shift_held: bool) -> void:
    if shift_held:
        if selected_paths.has(path):
            selected_paths.erase(path)
        else:
            selected_paths.append(path)
    else:
        selected_paths = [path]
    _rebuild_bulk_proxy()
    selection_changed.emit()


func select_resource_range(from_path: String, to_path: String) -> void:
    ## For Shift+Click range select. Finds indices in resources array
    ## and selects everything in between.
    var from_idx: int = _index_of_path(from_path)
    var to_idx: int = _index_of_path(to_path)
    if from_idx == -1 or to_idx == -1: return
    var lo: int = mini(from_idx, to_idx)
    var hi: int = maxi(from_idx, to_idx)
    selected_paths.clear()
    for i: int in range(lo, hi + 1):
        selected_paths.append(resources[i].resource_path)
    _rebuild_bulk_proxy()
    selection_changed.emit()


func deselect_all() -> void:
    selected_paths.clear()
    _clear_bulk_proxy()
    selection_changed.emit()


func create_resource(target_path: String) -> void:
    var script_path: String = _get_class_script_path(selected_class)
    if script_path.is_empty():
        error_raised.emit("No script found for class '%s'" % selected_class)
        return
    var script: GDScript = load(script_path)
    if script == null:
        error_raised.emit("Failed to load script at '%s'" % script_path)
        return
    var instance: Resource = script.new()
    var err: Error = ResourceSaver.save(instance, target_path)
    if err != OK:
        error_raised.emit("Failed to save resource at '%s'" % target_path)


func delete_resources(paths: Array[String]) -> void:
    var failed: Array[String] = []
    for path: String in paths:
        if not path.begins_with("res://"):
            failed.append(path)
            continue
        var err: Error = DirAccess.remove_absolute(
            ProjectSettings.globalize_path(path))
        if err != OK:
            failed.append(path)
    # Remove deleted from selection
    for path: String in paths:
        selected_paths.erase(path)
    if not failed.is_empty():
        var capped: String = "\n".join(failed.slice(0, 10))
        if failed.size() > 10:
            capped += "\n... and %d more" % (failed.size() - 10)
        error_raised.emit("Failed to delete:\n%s" % capped)
    selection_changed.emit()


func apply_bulk_edit(property: String) -> void:
    if bulk_proxy == null: return
    var new_value: Variant = bulk_proxy.get(property)
    # Deep-duplicate reference types
    if new_value is Array or new_value is Dictionary:
        new_value = new_value.duplicate(true)
    var failed: Array[String] = []
    var succeeded: Array[Resource] = []
    for res: Resource in _get_selected_resources():
        # Only set if resource owns the property
        if not _resource_has_property(res, property): continue
        res.set(property, new_value)
        var err: Error = ResourceSaver.save(res, res.resource_path)
        if err != OK:
            failed.append(res.resource_path)
        else:
            succeeded.append(res)
    if not failed.is_empty():
        error_raised.emit("Failed to save:\n%s" % "\n".join(failed))
    if not succeeded.is_empty():
        state_changed.emit()  # Views refresh affected rows


func on_filesystem_changed() -> void:
    ## Called by Window when EditorFileSystem.filesystem_changed fires.
    ## Window owns the debounce timer (it's a Node concern).
    rescan()


func rescan() -> void:
    if selected_class.is_empty(): return
    _refresh_maps()
    _check_classes_changed()
    _scan_and_notify()
```

### Internal helpers (private)

```gdscript
func _scan_and_notify() -> void:
    resolved_class_names = _resolve_class_names()
    columns = ProjectClassScanner.unite_classes_properties(
        resolved_class_names, _global_classes_map)
    var root: EditorFileSystemDirectory = \
        EditorInterface.get_resource_filesystem().get_filesystem()
    if not is_instance_valid(root):
        resources = []
    else:
        resources = ProjectClassScanner.load_classed_resources_from_dir(
            resolved_class_names, root)
    # Prune stale selections
    var valid_paths: Dictionary = {}
    for res: Resource in resources:
        valid_paths[res.resource_path] = true
    selected_paths = selected_paths.filter(
        func(p: String): return valid_paths.has(p))
    status_text = "%d resource(s) found" % resources.size()
    _rebuild_bulk_proxy()
    state_changed.emit()


func _resolve_class_names() -> Array[String]:
    if not include_subclasses:
        return [selected_class]
    return ProjectClassScanner.get_descendant_classes(
        selected_class, _classes_parent_map)


func _rebuild_bulk_proxy() -> void:
    _clear_bulk_proxy()
    var selected_resources: Array[Resource] = _get_selected_resources()
    if selected_resources.is_empty(): return
    var script: GDScript = selected_resources[0].get_script() \
        if selected_resources.size() == 1 \
        else _get_class_script(selected_class)
    if script == null: return
    bulk_proxy = script.new()
    for prop: Dictionary in script.get_script_property_list():
        var value: Variant = selected_resources[0].get(prop.name)
        if value is Array or value is Dictionary:
            value = value.duplicate(true)
        bulk_proxy.set(prop.name, value)
    selection_changed.emit()


func _clear_bulk_proxy() -> void:
    bulk_proxy = null


func _get_selected_resources() -> Array[Resource]:
    var result: Array[Resource] = []
    for res: Resource in resources:
        if selected_paths.has(res.resource_path):
            result.append(res)
    return result


func _resource_has_property(res: Resource, prop_name: String) -> bool:
    for p: Dictionary in res.get_script().get_script_property_list():
        if p.name == prop_name:
            return true
    return false
```

---

## Views — What They Become

### Window (thin shell)

The Window becomes a thin shell. Its only jobs:
1. Create the ViewModel
2. Pass it to children
3. Own the debounce timer (Node concern, can't live in RefCounted)
4. Connect `EditorFileSystem.filesystem_changed` → timer → `vm.on_filesystem_changed()`
5. Connect `EditorInspector.property_edited` → `vm.apply_bulk_edit()`
6. Push `vm.bulk_proxy` to Inspector when selection changes

```gdscript
@tool
extends Window

var vm: VREViewModel = VREViewModel.new()

func _ready() -> void:
    if not Engine.is_editor_hint(): return

    # Pass ViewModel to all children
    %ClassSelector.vm = vm
    %ResourceList.vm = vm

    # ViewModel signals → UI updates
    vm.state_changed.connect(_on_vm_state_changed)
    vm.selection_changed.connect(_on_vm_selection_changed)
    vm.classes_changed.connect(_on_vm_classes_changed)
    vm.error_raised.connect(%ErrorDialog.show_error)

    # EditorFileSystem → debounce → ViewModel
    var efs: EditorFileSystem = EditorInterface.get_resource_filesystem()
    if efs:
        efs.filesystem_changed.connect(_on_filesystem_changed)
    %RescanDebounceTimer.timeout.connect(vm.on_filesystem_changed)

    # Inspector → ViewModel
    var inspector: EditorInspector = EditorInterface.get_inspector()
    if inspector:
        inspector.property_edited.connect(_on_inspector_property_edited)

    # Initialize
    vm.initialize()


func _on_vm_state_changed() -> void:
    # ResourceList auto-updates via its own vm connection
    pass


func _on_vm_selection_changed() -> void:
    if vm.bulk_proxy:
        EditorInterface.inspect_object(vm.bulk_proxy)
    else:
        EditorInterface.inspect_object(null)


func _on_vm_classes_changed(added: Array[String], removed: Array[String]) -> void:
    # ClassSelector auto-updates via its own vm connection
    pass


func _on_filesystem_changed() -> void:
    %RescanDebounceTimer.start()


func _on_inspector_property_edited(property: String) -> void:
    var inspector: EditorInspector = EditorInterface.get_inspector()
    if inspector and inspector.get_edited_object() == vm.bulk_proxy:
        vm.apply_bulk_edit(property)
```

**Window dropped**: all class-setting, save-routing, delete-routing, selection-forwarding. It's ~40 lines instead of the current ~50+ with growth trajectory.

### ClassSelector View

```gdscript
@tool
extends HBoxContainer

signal class_selected(class_name_str: String)

var vm: VREViewModel : set = _set_vm

func _set_vm(value: VREViewModel) -> void:
    vm = value
    if vm:
        vm.classes_changed.connect(_on_classes_changed)
        _rebuild_dropdown()


func _on_classes_changed(_added: Array[String], _removed: Array[String]) -> void:
    _rebuild_dropdown()


func _rebuild_dropdown() -> void:
    var prev: String = _get_selected_text()
    %ClassDropdown.clear()
    %ClassDropdown.add_item("-- Select a class --", 0)
    var sorted: Array[String] = vm.available_classes.duplicate()
    sorted.sort_custom(func(a: String, b: String): return a.nocasecmp_to(b) < 0)
    for i: int in range(sorted.size()):
        %ClassDropdown.add_item(sorted[i], i + 1)
    # Restore selection
    if not prev.is_empty():
        var idx: int = sorted.find(prev)
        if idx != -1:
            %ClassDropdown.select(idx + 1)


func _on_class_dropdown_item_selected(index: int) -> void:
    if index == 0: return
    var class_name_str: String = %ClassDropdown.get_item_text(index)
    vm.select_class(class_name_str)


func _get_selected_text() -> String:
    if %ClassDropdown.selected > 0:
        return %ClassDropdown.get_item_text(%ClassDropdown.selected)
    return ""
```

**Dropped**: `set_classes()`, `add_class()`, `remove_class()` — all replaced by reading `vm.available_classes` when `classes_changed` fires. No internal `_classes_names` state.

### ResourceList View

```gdscript
@tool
class_name ResourceListView
extends VBoxContainer

var vm: VREViewModel : set = _set_vm
var _rows: Array[ResourceRow] = []
var _path_to_row: Dictionary = {}   # String → ResourceRow

func _set_vm(value: VREViewModel) -> void:
    vm = value
    if vm:
        vm.state_changed.connect(_on_state_changed)
        vm.selection_changed.connect(_on_selection_changed)


func _ready() -> void:
    %CreateBtn.pressed.connect(func(): _show_create_dialog())
    %DeleteSelectedBtn.pressed.connect(func(): _show_delete_dialog())
    %RefreshBtn.pressed.connect(func(): vm.rescan())


func _on_state_changed() -> void:
    _rebuild_rows()
    _sync_selection_ui()
    %StatusLabel.text = vm.status_text


func _on_selection_changed() -> void:
    _sync_selection_ui()


func _rebuild_rows() -> void:
    _clear_rows()
    %HeaderRow.columns = vm.columns
    for res: Resource in vm.resources:
        var row: ResourceRow = RESOURCE_ROW_SCENE.instantiate()
        row.resource = res
        row.columns = vm.columns
        %RowsContainer.add_child(row)
        row.resource_row_clicked.connect(_on_row_clicked)
        row.delete_clicked.connect(_on_row_delete)
        _rows.append(row)
        _path_to_row[res.resource_path] = row


func _sync_selection_ui() -> void:
    for row: ResourceRow in _rows:
        if is_instance_valid(row):
            row.set_selected(vm.selected_paths.has(row.resource.resource_path))
    var count: int = vm.selected_paths.size()
    %DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 \
        else "Delete Selected"


func _on_row_clicked(resource_path: String, shift_held: bool) -> void:
    vm.select_resource(resource_path, shift_held)


func _on_row_delete(resource_path: String) -> void:
    _show_delete_confirmation([resource_path])


func _show_delete_dialog() -> void:
    _show_delete_confirmation(vm.selected_paths.duplicate())
```

**Dropped**: `selected_rows` state (lives in ViewModel now), `_resource_to_row` keyed by Resource (now by path), all selection logic (ViewModel decides).

### ResourceRow View

```gdscript
# Emits paths now, not Resource references
signal resource_row_clicked(resource_path: String, shift_held: bool)
signal delete_clicked(resource_path: String)
```

Row becomes even thinner — it just displays data and emits path-based intents.

---

## Data Flow Diagrams — MVVM

### Class Selection

```
User clicks ClassDropdown
        │
        ▼
ClassSelector._on_class_dropdown_item_selected(index)
        │
        ▼ calls
vm.select_class("Weapon")
        │
        ├── selected_class = "Weapon"
        ├── _scan_and_notify()
        │       ├── resolve class names (base + descendants)
        │       ├── compute column union
        │       ├── load matching .tres files
        │       ├── prune stale selections
        │       └── state_changed.emit()
        │                  │
        │       ┌──────────┴──────────┐
        │       ▼                     ▼
        │  ResourceList           (any future
        │  ._on_state_changed()    listener)
        │       │
        │       ├── _rebuild_rows()
        │       └── _sync_selection_ui()
        │
        └── (done — no Window routing needed)
```

### Resource Selection (Multi-Select)

```
User clicks ResourceRow
        │
        ▼
ResourceRow._on_pressed()
        │ emits resource_row_clicked(path, shift_held)
        ▼
ResourceList._on_row_clicked(path, shift)
        │
        ▼ calls
vm.select_resource(path, shift)
        │
        ├── update selected_paths (toggle or replace)
        ├── _rebuild_bulk_proxy()
        │       ├── create proxy Resource
        │       └── populate from first selected
        ├── selection_changed.emit()
        │           │
        │    ┌──────┴──────────────┐
        │    ▼                     ▼
        │  ResourceList        Window
        │  ._on_selection_     ._on_vm_selection_
        │   changed()           changed()
        │    │                    │
        │    └─ _sync_selection   └─ EditorInterface
        │       _ui() (toggle       .inspect_object
        │        row highlights)     (vm.bulk_proxy)
        │
        └── (done)
```

### Bulk Edit Property

```
User edits property in Inspector
        │
        ▼
EditorInspector.property_edited(property_name)
        │
        ▼
Window._on_inspector_property_edited(property)
        │ checks: edited_object == vm.bulk_proxy?
        ▼ calls
vm.apply_bulk_edit(property)
        │
        ├── get new_value from bulk_proxy
        ├── duplicate if Array/Dict (fix ref mutation)
        ├── for each selected resource:
        │       ├── check _resource_has_property()
        │       ├── res.set(property, new_value)
        │       └── ResourceSaver.save(res)
        ├── collect failures → error_raised.emit()
        └── state_changed.emit()
                    │
                    ▼
              ResourceList._on_state_changed()
                    └── _rebuild_rows() (rows refresh)
```

### Create Resource

```
User clicks "New" → SaveResourceDialog confirms path
        │
        ▼
Dialog returns target_path
        │
        ▼ calls
vm.create_resource(target_path)
        │
        ├── load class script
        ├── instantiate Resource
        ├── ResourceSaver.save()
        ├── on error → error_raised.emit()
        └── (filesystem_changed will trigger rescan via debounce)
```

### Delete Resources

```
User confirms deletion in ConfirmDeleteDialog
        │
        ▼ calls
vm.delete_resources(paths)
        │
        ├── validate each path begins_with("res://")
        ├── DirAccess.remove_absolute() each
        ├── prune deleted from selected_paths
        ├── on failures → error_raised.emit()
        ├── selection_changed.emit()
        └── (filesystem_changed will trigger rescan via debounce)
```

### Filesystem Change (External)

```
External file change detected by Godot
        │
        ▼
EditorFileSystem.filesystem_changed
        │
        ▼
Window._on_filesystem_changed()
        │
        ▼
%RescanDebounceTimer.start()   ← 0.1s, one_shot
        │
        ▼ (after 0.1s)
vm.on_filesystem_changed()
        │
        ▼
vm.rescan()
        ├── _refresh_maps()
        ├── _check_classes_changed()
        │       └── classes_changed.emit() if changed
        │               └── ClassSelector._on_classes_changed()
        │                       └── _rebuild_dropdown()
        └── _scan_and_notify()
                └── state_changed.emit()
                        └── ResourceList._on_state_changed()
                                └── _rebuild_rows()
```

---

## File Changes — Migration Plan

### New Files

| File | Type | Purpose |
|------|------|---------|
| `core/vre_view_model.gd` | ViewModel | All state + business logic. RefCounted. |

### Modified Files

| File | Changes |
|------|---------|
| `ui/visual_resources_editor_window.gd` | Strip to thin shell: create VM, pass to children, own timer + inspector bridge |
| `ui/visual_resources_editor_window.tscn` | Remove `%VREStateManager` scene instance, remove `%BulkEditor` node. Add `%RescanDebounceTimer` directly. Keep dialogs. |
| `ui/class_selector/class_selector.gd` | Replace internal `_classes_names` with `vm.available_classes`. Listen to `vm.classes_changed`. |
| `ui/resource_list/resource_list.gd` | Remove `selected_rows`. Key by path not Resource. Listen to `vm.state_changed` + `vm.selection_changed`. |
| `ui/resource_list/resource_row.gd` | Emit paths not Resources. |

### Deleted Files

| File | Reason |
|------|--------|
| `core/state_manager.gd` | Absorbed into VREViewModel |
| `core/state_manager.tscn` | No longer needed (VM is RefCounted, timer moves to Window) |
| `core/bulk_editor.gd` | Absorbed into VREViewModel |

### Unchanged Files

| File | Why |
|------|-----|
| `core/project_class_scanner.gd` | Pure static utility — stays as Model layer |
| `ui/resource_list/header_row.gd` | Pure display — already thin |
| `ui/resource_list/resource_field_label.tscn` | Scene resource — unchanged |
| `ui/resource_list/header_field_label.tscn` | Scene resource — unchanged |
| `ui/resource_list/field_separator.tscn` | Scene resource — unchanged |
| `ui/resource_list/resource_row.tscn` | Scene structure unchanged, only script signals change |
| `ui/dialogs/error_dialog.gd` | Pure display — unchanged |
| `visual_resources_editor_plugin.gd` | Entry point — unchanged |
| `visual_resources_editor_toolbar.gd` | Launcher — unchanged |

---

## What This Fixes From visual_resources_fixes.md

Moving to MVVM directly resolves or simplifies many items from the fix list:

| Fix # | Problem | How MVVM resolves it |
|-------|---------|---------------------|
| 4, 10, 22 | Uncached get_global_class_list | Single `_refresh_maps()` in VM, all lookups use cached maps |
| 5 | Ref-type mutation in bulk proxy | VM's `_rebuild_bulk_proxy()` does `.duplicate(true)` |
| 6 | Stale EditorInspector cache | Window fetches fresh inspector in callback, no cached member |
| 7 | Bulk proxy not cleaned up | VM's `_clear_bulk_proxy()` called on empty selection and on rebuild |
| 8 | Bulk edit on wrong subclass | VM's `apply_bulk_edit()` checks `_resource_has_property()` |
| 9 | Partial save emits full success | VM tracks succeeded vs failed separately |
| 11 | Error output overflow | VM caps error messages to 10 paths |
| 13 | Premature initialization | VM initialized explicitly via `vm.initialize()` in Window._ready() |
| 15 | Unnecessary getters | VM exposes state directly as properties, no getters needed |
| 16 | Empty class list no warning | VM checks in `_scan_and_notify()` |
| 23 | SaveDialog calls scan() directly | VM owns create logic, doesn't call scan() — lets filesystem_changed propagate |
| 25 | Signal connection leak | ResourceList disconnects in `_clear_rows()` (fix applied during migration) |
| 26 | Null pointer in selection | Selection is by path (String), not by Resource reference — no stale refs |
| 29 | Stale resource refs after rescan | Paths survive rescans — Resources don't |
| 41 | No path validation on delete | VM validates `path.begins_with("res://")` |

---

## What MVVM Does NOT Fix

These remain as separate work items regardless of architecture:

| Fix # | Problem | Why separate |
|-------|---------|-------------|
| 1 | tres full-load performance | Model layer concern (ProjectClassScanner) — orthogonal to MVVM |
| 17 | Full rescan on fs change | Incremental scanning is a Model optimization |
| 20 | Dict .has() ref equality | ProjectClassScanner bug — fix in scanner |
| 21 | PROPERTY_USAGE_EDITOR filter | Scanner + Row — fix in both |
| 27, 28 | Shift=range / input detection | UX behavior — implement in VM's `select_resource_range()` + Row's `_gui_input()` |
| 31 | No row virtualization | View optimization — can be done after MVVM migration |
| 32 | StyleBox memory bloat | View concern — fix in ResourceRow independently |
| 44 | Plugin typo "shubmenu" | Unrelated to architecture |

---

## Migration Strategy

### Phase 1: Create VREViewModel (non-breaking)

1. Create `core/vre_view_model.gd` with all state and methods
2. Write tests against the ViewModel directly (no scene tree needed)
3. Verify: all existing tests still pass

### Phase 2: Wire Window to ViewModel

1. Window creates VM, passes to children
2. Window connects VM signals
3. StateManager + BulkEditor still exist but are now thin wrappers delegating to VM
4. Verify: plugin works identically

### Phase 3: Migrate Views

1. ClassSelector reads from VM instead of internal state
2. ResourceList reads from VM, selections by path
3. ResourceRow emits paths
4. Verify: plugin works identically

### Phase 4: Delete Old Code

1. Delete `state_manager.gd`, `state_manager.tscn`, `bulk_editor.gd`
2. Update `window.tscn` to remove those nodes
3. Clean up any remaining direct-wiring in Window

Each phase is one commit. Plugin works at every step.
