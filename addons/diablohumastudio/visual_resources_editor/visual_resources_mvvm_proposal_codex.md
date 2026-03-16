# Visual Resources Editor — MVVM Proposal (Codex)

This proposal keeps the plugin's current UI and features, but shifts orchestration and business rules into a ViewModel so UI nodes stop talking to each other and the Window stops routing every signal. The result is a smaller surface area for bugs, easier tests, and a clean place to grow features like filters, sorting, and column presets.

---

## Goals

- Remove Window as signal router and state hub
- Centralize all mutable state in a single ViewModel
- Make UI nodes purely presentational and interaction-driven
- Enable unit tests for selection, scan, and bulk-edit logic without scenes

---

## Proposed MVVM Structure

### 1) Model Layer (unchanged APIs)

These are your existing persistence and editor APIs. They remain stateless utilities, invoked only from the ViewModel:

- `ProjectClassScanner`
- `EditorFileSystem`
- `ResourceSaver`, `DirAccess`, `ProjectSettings`

### 2) ViewModel Layer (new)

A single `RefCounted` object owns state and logic. It exposes state via properties and emits signals on change.

- `VREViewModel` (new)
- Optional thin `VRERepository` (new) to wrap filesystem + class scanning

### 3) View Layer (existing scenes)

All current `.tscn` scenes remain but get thinner scripts that bind to the ViewModel. Views do not talk to each other.

- `visual_resources_editor_window.tscn` (host)
- `class_selector.tscn`
- `resource_list.tscn`
- `bulk_editor.gd`
- dialogs (`save_resource_dialog`, `confirm_delete_dialog`, `error_dialog`)

---

## Architecture Diagrams

### High-level MVVM

```
┌──────────────────────────────────────────────────────────┐
│                        MODEL                             │
│  ProjectClassScanner, EditorFileSystem, ResourceSaver    │
└────────────────────────────┬─────────────────────────────┘
                             │ called by
                             ▼
┌──────────────────────────────────────────────────────────┐
│                     VREViewModel                          │
│   RefCounted: owns ALL state + logic                      │
│   emits signals; no Node access                           │
└────────────────────────────┬─────────────────────────────┘
                             │ observed/called by
        ┌────────────────────┼─────────────────────┐
        ▼                    ▼                     ▼
┌──────────────┐     ┌─────────────────┐   ┌────────────────┐
│ClassSelector │     │ResourceList      │   │Dialogs + Bulk  │
│(View)        │     │(View)            │   │Editor (View)   │
└──────────────┘     └─────────────────┘   └────────────────┘
```

### Current vs MVVM Flow (simplified)

```
Current:
Window -> StateManager -> ResourceList
Window -> BulkEditor
Window -> Save/Delete dialogs
ResourceList -> BulkEditor (selection)

MVVM:
Window -> VREViewModel
Views <-> VREViewModel (signals + methods)
No View -> View wiring
```

### Selection Flow (sequence)

```
User clicks row
  -> ResourceList emits ui event
    -> ResourceList calls vm.select_path(path, modifiers)
      -> vm updates selected_paths
        -> vm emits selection_changed(paths)
          -> BulkEditor updates preview
          -> ResourceList updates highlight
```

---

## ViewModel Design

### Public Signals

- `classes_changed(added: Array[String], removed: Array[String])`
- `state_changed()` (for broad changes like data reloads)
- `selection_changed(paths: Array[String])`
- `error_raised(message: String)`
- `status_changed(text: String)` (optional)

### Public State (read-only for Views)

- `available_classes: Array[String]`
- `selected_class: String`
- `include_subclasses: bool`
- `resources: Array[Resource]`
- `columns: Array[Dictionary]`
- `selected_paths: Array[String]`
- `bulk_proxy: Resource` (optional for editor binding)
- `status_text: String`

### Commands (Views call)

- `initialize()`
- `select_class(name: String)`
- `set_include_subclasses(value: bool)`
- `rescan()`
- `select_path(path: String, additive: bool, range: bool)`
- `create_resource(target_path: String)`
- `delete_resources(paths: Array[String])`
- `apply_bulk_edit(property: String, value: Variant)`
- `refresh_row(path: String)` (optional)

---

## Mapping Current Scripts to MVVM

### Current

- `ui/visual_resources_editor_window.gd` routes signals and sets state on other nodes
- `core/state_manager.gd` owns class scanning and resource list state
- `core/bulk_editor.gd` both edits and manages selection + persistence
- `ui/resource_list/resource_list.gd` owns selection semantics
- dialogs call filesystem or state manager directly

### Proposed Mapping

- `core/state_manager.gd` becomes logic inside `VREViewModel`
- `core/bulk_editor.gd` becomes a View, no persistence
- `resource_list.gd` becomes a View; selection logic moves to ViewModel
- dialogs just call ViewModel commands
- `visual_resources_editor_window.gd` only creates VM and injects it into children

---

## Suggested File Additions

- `addons/diablohumastudio/visual_resources_editor/core/vre_view_model.gd`
- `addons/diablohumastudio/visual_resources_editor/core/vre_repository.gd` (optional)

If you want to keep the names consistent with current structure, place the ViewModel in `core/` and keep Views in `ui/`.

---

## Example ViewModel Skeleton

```gdscript
# addons/diablohumastudio/visual_resources_editor/core/vre_view_model.gd
class_name VREViewModel
extends RefCounted

signal classes_changed(added: Array[String], removed: Array[String])
signal state_changed()
signal selection_changed(paths: Array[String])
signal error_raised(message: String)

var available_classes: Array[String] = []
var selected_class: String = ""
var include_subclasses: bool = true
var resources: Array[Resource] = []
var columns: Array[Dictionary] = []
var selected_paths: Array[String] = []

func initialize() -> void:
    _refresh_classes()
    _rescan()

func select_class(name: String) -> void:
    if selected_class == name:
        return
    selected_class = name
    _rescan()

func set_include_subclasses(value: bool) -> void:
    if include_subclasses == value:
        return
    include_subclasses = value
    _rescan()

func select_path(path: String, additive: bool, range: bool) -> void:
    # Selection algorithm lives here, not in ResourceList
    # Update selected_paths then emit selection_changed
    selection_changed.emit(selected_paths)

func _refresh_classes() -> void:
    var new_classes := ProjectClassScanner.get_resource_classes_in_folder({})
    # Compute added/removed here
    available_classes = new_classes
    classes_changed.emit(available_classes, [])

func _rescan() -> void:
    # Use EditorFileSystem / ProjectSettings to build resources + columns
    state_changed.emit()
```

---

## How Views Bind to the ViewModel

### Window (host)

Responsibilities:

- Instantiate ViewModel
- Inject it into child Views
- Connect editor events to ViewModel (e.g., filesystem changed)

```
Window
  - vm := VREViewModel.new()
  - class_selector.set_view_model(vm)
  - resource_list.set_view_model(vm)
  - bulk_editor.set_view_model(vm)
  - dialogs.set_view_model(vm)
```

### Example View Binding (ResourceList)

```
ResourceList._ready():
  vm.state_changed.connect(_on_vm_state_changed)
  vm.selection_changed.connect(_on_vm_selection_changed)

_on_vm_state_changed():
  render rows

_on_vm_selection_changed(paths):
  update highlights

_on_row_clicked(path, modifiers):
  vm.select_path(path, modifiers.additive, modifiers.range)
```

---

## Migration Plan (incremental)

1. Add `VREViewModel` with minimal state: class list + include_subclasses
2. Move class scan and resource scan from `state_manager.gd` into ViewModel
3. Update Window to build VM and inject into children
4. Update `class_selector.gd` and `resource_list.gd` to use VM signals
5. Move selection logic from `resource_list.gd` into ViewModel
6. Move bulk edit persistence from `bulk_editor.gd` into ViewModel
7. Update dialogs to call ViewModel commands
8. Remove direct View-to-View wiring from Window

---

## Testing Angle

Once the ViewModel exists, tests can instantiate it directly and assert:

- Class scanning results
- Selection behavior (single, multi, range)
- Bulk edit application
- Delete/create flows

This is not possible today without scene instantiation.

---

## Optional: Repository Layer

If ViewModel starts to feel large, you can add `VRERepository` to hide Godot API calls:

```
VREViewModel
  -> VRERepository
     - list_classes()
     - list_resources(class, include_subclasses)
     - save_resource(resource)
     - delete_resources(paths)
```

This keeps ViewModel focused on orchestration and state, while repository handles file IO.

---

## Summary

MVVM for this plugin means one new core object (`VREViewModel`), thin UI scripts, and the removal of Window-as-orchestrator. It keeps your UI scenes intact and makes the plugin easier to extend and test without rewriting the UI.
