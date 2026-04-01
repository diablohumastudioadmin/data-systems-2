# VRE Architecture Analysis

Harsh, honest review of the Visual Resources Editor plugin.

---

## The Good

The foundation is solid. The MVVM-ish pattern with a central `VREStateManager` is the right call for a plugin like this. Components don't know about each other, all communication flows through state signals, and the window is a pure dependency injector. This is clean and testable in principle.

Specific wins:
- **Incremental mtime-based change detection** instead of full rescans on every filesystem event. Smart.
- **Pagination** keeps the UI responsive with large resource sets.
- **DebounceTimer** prevents rapid-fire rescans when the filesystem floods events.
- **`get_class_from_tres_file()`** reading only the first line instead of loading the entire resource. Good performance instinct.
- **The property setter + `_ready()` guard** pattern is consistent across all components now. No more `initialize()` methods with ambiguous call timing.
- **`res://` guard** on delete operations. Small thing, but prevents a class of dangerous bugs.

---

## Critical Issues

### 1. StateManager is a 472-line god object

It handles: class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic (shift/ctrl/none), filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and signal emission for 12 different signals.

That's at least 6 distinct responsibilities crammed into one file. The method `_handle_global_classes_updated()` alone is a 35-line decision tree with 5 branching paths, each with side effects. You can't test any of these concerns in isolation.

Gemini agrees and frames the solution well: use a **Coordinator pattern**. `ClassRepository`, `ResourceRepository`, `SelectionManager`, and `PaginationManager` should be isolated pieces — none knowing the other exists. The coordinator (the new thin `VREStateManager`) listens to `ClassRepository.classes_changed` and passes the updated class list to `ResourceRepository`. This solves the "they need to share data" problem without coupling them: the coordinator is the only one who sees both.

**What to do:** Split into focused pieces:
- `ClassRegistry`: owns class maps, resolves descendants, detects renames/deletions.
- `ResourceRepository`: owns resource loading, mtime tracking, change detection.
- `SelectionManager`: owns selected_resources, handles shift/ctrl/none logic.
- `PaginationManager`: owns page slicing and page-level change detection.
- `VREStateManager` becomes a thin coordinator that wires these together.

**Effort: High.** This is a multi-session refactor. But it's the single most impactful change you could make. Every other improvement gets easier once state_manager is decomposed.

---

### 2. Scattered Resource Saving

`VREStateManager` calls `ResourceSaver.save()` directly in `_resave_orphaned_resources()` and `_handle_property_changes()`. `BulkEditor` also has its own `ResourceSaver.save()` loop with its own failure list and error reporting.

If you ever need to change how saving works — add logging, add a confirmation step, defer saves — you have to hunt down multiple places.

**What to do:** Centralize all disk writes into a single `ResourceRepository` (or `StorageManager`). It handles saving, error reporting via `state_manager.report_error()`, and post-save filesystem scanning. `VREStateManager` and `BulkEditor` tell it what to save; they don't call `ResourceSaver` directly.

**Effort: Medium.** Mechanical but touches two files and requires deciding on the API.

---

## Worth Considering

### 1. Use the EditorFilesystemListener properly

There is a `core/editor_filesystem_listener.gd` file, yet `VREStateManager` still connects directly to `EditorInterface.get_resource_filesystem()` signals in its own `_ready()`. The listener is unused for its intended purpose.

**What to do:** Route all filesystem signal handling through the listener. It emits generic `file_changed` / `files_deleted` signals. `VREStateManager` subscribes to those instead of the editor filesystem directly. This decouples the data layer from the Godot editor interface and makes `VREStateManager` testable without a running editor.

**Effort: Low-Medium.**

---

### 2. Narrow the state_manager injection

Every UI component receives the full `VREStateManager`. `PaginationBar` only needs `prev_page`, `next_page`, and `pagination_changed`. `ResourceList` only needs resource data and selection. Passing the whole manager to every component makes the dependency surface larger than necessary.

**What to do** (after the StateManager split): pass only the sub-manager each component actually needs. `PaginationBar` gets a `PaginationManager`. `ResourceList` gets a `ResourceRepository` and `SelectionManager`. UI components become independently testable.

**Effort: Low** (after the split — not worth doing before it).

---

## The Ugly (probably not worth fixing)

### 1. O(N) linear scan in `_scan_class_resources_for_changes()`

The inner loop `for i in updated_class_resources.size(): if path == ...` does a linear search to find and replace a modified resource. With 1000+ resources and frequent filesystem events, this adds up.

A `Dictionary[String, int]` mapping path to index would make this O(1), but the debounce timer makes this fire at most once per 100ms, and the resources are already paginated. Probably fine in practice.

**Effort: Low, but low value too.** Only matters with very large resource sets and frequent external edits.

---

### 2. Strict MVVM (ViewModel layer)

Right now UI components bind directly to domain objects — `ResourceRow` knows what a `Resource` is, what `ResourceProperty` is, and holds a reference to `VREStateManager`. In a strict MVVM pattern, `ResourceRow` would only know about a `ResourceItemViewModel` — a plain data struct with display strings — and have zero knowledge of Godot's domain objects.

This makes the UI completely stateless, independently testable (pass a fake ViewModel with no `.tres` file), and insulated from changes in the data layer. The bulk editor case becomes elegant: modifying 50 resources just updates each ViewModel, and the rows update automatically.

It is, however, a ground-up rethink of how data flows through the plugin.

**Effort: Very high.** Worthwhile only if the plugin grows into a large, long-lived tool.

---

## Priority Ranking

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| **1** | Split StateManager into focused pieces | High | Testability, maintainability, unlocks everything else |
| **2** | Centralize resource saving | Medium | Correctness, eliminates duplicate save logic |
| **3** | Use EditorFilesystemListener properly | Low-Medium | Decoupling, testability |
| **4** | Narrow state_manager injection (after split) | Low | Cleaner dependencies |

Items 1-2 address real correctness and maintainability problems. Items 3-4 are clean-up that follows naturally from the split. The Ugly items are left alone unless the project scales significantly.

---

## Architecture Diagram (Current)

```
Plugin Entry
  VisualResourcesEditorPlugin
    └─ VisualResourcesEditorToolbar (menu item, singleton window)

Window (pure DI coordinator)
  VisualResourcesEditorWindow._ready()
    ├─ %ClassSelector.state_manager = state
    ├─ %SubclassFilter.state_manager = state
    ├─ %ResourceList.state_manager = state
    ├─ %Toolbar.state_manager = state
    ├─ %BulkEditor.state_manager = state
    ├─ %PaginationBar.state_manager = state
    ├─ %StatusLabel.state_manager = state
    └─ %Dialogs.state_manager = state

State (god object, 472 LOC)
  VREStateManager
    ├─ Class maps (global_class_map, parent_map, path_map, name_list)
    ├─ Current class state (name, script, properties, included classes)
    ├─ Resource tracking (resources, mtimes, page slice, page mtimes)
    ├─ Selection (selected_resources, last_index)
    ├─ Pagination (_current_page, PAGE_SIZE)
    ├─ Filesystem listening (EditorFileSystem signals → debounce → rescan)
    └─ 12 signals out to UI

Scanner (stateless utility)
  ProjectClassScanner
    ├─ Build class maps from ProjectSettings
    ├─ Scan filesystem for .tres by class
    └─ Extract properties from GDScript

UI Components (all read-only views of state)
  ClassSelector ──listens──→ project_classes_changed, current_class_renamed
  SubclassFilter ──calls──→ state_manager.set_include_subclasses()
  ResourceList ──listens──→ 6 resource signals + selection + edited
    └─ ResourceRow ──calls──→ state_manager.set_selected_resources()
  Toolbar ──listens──→ selection_changed
  PaginationBar ──listens──→ pagination_changed
  StatusLabel ──listens──→ resources_replaced/added/removed, selection
  BulkEditor ──listens──→ selection_changed, EditorInspector.property_edited
  Dialogs
    ├─ SaveResourceDialog ──listens──→ create_new_resource_requested
    ├─ ConfirmDeleteDialog ──listens──→ delete_selected_requested
    └─ ErrorDialog ──listens──→ error_occurred
```

## Architecture Diagram (Proposed after StateManager split)

```
VREStateManager (thin coordinator, ~80 LOC)
  ├─ ClassRegistry        ← class maps, rename detection, descendant resolution
  ├─ ResourceRepository   ← resource loading, mtime tracking, change detection, saving
  ├─ SelectionManager     ← shift/ctrl/none logic, selected_resources
  ├─ PaginationManager    ← page slicing, page-level diffs
  └─ FilesystemListener   ← EditorFileSystem signals, debounce, suppression

UI components unchanged — they still talk to VREStateManager.
VREStateManager delegates internally.
Each piece is independently testable with stubs.
```
