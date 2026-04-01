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

## The Bad

### 1. StateManager is a 472-line god object

It handles: class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic (shift/ctrl/none), filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and signal emission for 12 different signals.

That's at least 6 distinct responsibilities crammed into one file. The method `_handle_global_classes_updated()` alone is a 35-line decision tree with 5 branching paths, each with side effects. You can't test any of these concerns in isolation.

**What to do:** Split into focused pieces:
- `ClassRegistry` (or `ClassesRepository`): owns class maps, resolves descendants, detects renames/deletions.
- `ResourceRepository`: owns resource loading, mtime tracking, change detection.
- `SelectionManager`: owns selected_resources, handles shift/ctrl/none logic.
- `PaginationManager`: owns page slicing and page-level change detection.
- `VREStateManager` becomes a thin coordinator that wires these together.

**Effort: High.** This is a multi-session refactor. But it's the single most impactful change you could make. Every other improvement gets easier once state_manager is decomposed.

### 2. `_selected_paths` is parallel state waiting to diverge

`selected_resources` and `_selected_paths` are maintained in lockstep across 6 different code paths (shift, ctrl, no-key, restore, clear_view, and request_delete). Every mutation must update both. This is a bug waiting to happen.

`_selected_paths` exists solely so `_restore_selection()` can re-find resources after a rescan, and so `request_delete_selected_resources()` can emit paths. Neither justifies a parallel array.

**What to do:** Delete `_selected_paths`. Derive paths on demand:
```gdscript
func _get_selected_paths() -> Array[String]:
    return selected_resources.map(func(r: Resource) -> String: return r.resource_path)
```

**Effort: Low.** 30 minutes. High value.

### 3. Dialogs have duplicated and dead wiring

This is the messiest part of the codebase right now:

- **`SaveResourceDialog._connect_state()`** connects to `create_new_resource_requested` and handles it via `on_state_manager_create_new_resource_requested()` which references `%SaveResourceDialog` (itself!). This is the dialog connecting to a signal and then calling itself by unique name.
- **`Dialogs._connect_state()`** ALSO connects to `create_new_resource_requested` and calls `%SaveResourceDialog.show_create_dialog()`. So the signal fires twice, triggering two popup attempts.
- **`SaveResourceDialog.error_occurred`** signal is declared but emitted to nowhere. The errors in `_on_file_selected()` use `error_occurred.emit(...)` but nothing listens to that signal.
- **`ConfirmDeleteDialog.error_occurred`** same problem: emitted but unconnected. Delete errors vanish silently.

**What to do:**
- Remove `_connect_state()` and `on_state_manager_create_new_resource_requested()` from `SaveResourceDialog` entirely. `Dialogs.gd` already handles routing.
- Replace `error_occurred.emit(msg)` with `state_manager.report_error(msg)` in both dialogs (they already have `state_manager`).
- Remove the dead `error_occurred` signal declarations from both dialogs.

**Effort: Low.** 20 minutes. Fixes actual bugs (silent errors).

### 4. Two completely separate delete flows

ResourceRow has its own `%ConfirmDeleteDialog` (per-row, in the row's `.tscn`) that does `OS.move_to_trash()` + `update_file()` directly. The Toolbar has a separate delete flow through `state_manager.request_delete_selected_resources()` -> `ConfirmDeleteDialog` in the Dialogs scene.

The per-row delete:
- Bypasses state_manager completely
- Doesn't report errors through `state_manager.report_error()`
- Uses `push_warning` instead (only visible in console, not to user)
- Doesn't clear the deleted resource from `selected_resources`

This means: delete a resource via its row button while it's selected, and `selected_resources` still holds a reference to a freed resource until the next filesystem rescan picks it up.

**What to do:** Route per-row delete through state_manager too. Either:
- Have ResourceRow call `state_manager.request_delete_resource(resource)` (new method), or
- Remove the per-row delete entirely and rely on the toolbar's "Delete Selected" flow.

**Effort: Medium.** Requires deciding on the UX you want.

### 5. `ProjectClassScanner` rebuilds maps it doesn't need to

Most static methods accept an optional `global_class_map` parameter that defaults to `[]`, then calls `build_global_classes_map()` if empty. This means if you forget to pass the cached map, you silently pay for a full `ProjectSettings.get_global_class_list()` call. The API makes the expensive path the default.

Also, `get_properties_from_script_names()` accepts `global_class_to_path_map` but never passes it to `get_properties_from_script_name()`. So the inner call rebuilds the map every iteration. That's O(N * M) where M is the global class count.

**What to do:** Remove the default-empty-array pattern. Make the maps required parameters. If a caller doesn't have them, it should get them once and pass them. This makes the cost explicit.

**Effort: Low-Medium.** Mechanical but touches many call sites.

### 6. No cleanup on window close

`VisualResourcesEditorWindow._on_close_requested()` just calls `queue_free()`. But `VREStateManager._exit_tree()` disconnects from `EditorFileSystem` signals, and `BulkEditor._exit_tree()` cleans up the inspector connection. So cleanup does happen via the tree lifecycle.

However: the `VisualResourcesEditorToolbar` lambda `visual_resources_editor_window.close_requested.connect(func(): visual_resources_editor_window = null)` only nulls the reference on `close_requested`, not on `tree_exiting`. If the window is freed by something other than close_requested (e.g., parent freed), the toolbar keeps a dangling reference. The `is_instance_valid()` check in `open_visual_editor_window()` catches this, but it's sloppy.

**What to do:** Connect to `tree_exiting` instead of `close_requested` for the null-out.

**Effort: Trivial.** 1 line change.

---

## The Ugly (but probably not worth fixing)

### 7. O(N) linear scan in `_scan_class_resources_for_changes()`

The inner loop `for i in updated_class_resources.size(): if path == ...` does a linear search to find and replace a modified resource. With 1000+ resources and frequent filesystem events, this adds up.

A `Dictionary[String, int]` mapping path to index would make this O(1), but the debounce timer makes this fire at most once per 100ms, and the resources are already paginated. Probably fine in practice.

**Effort: Low, but low value too.** Only matters with very large resource sets and frequent external edits.

### 8. `_handle_property_changes()` resaves ALL resources on property schema change

When a class script's properties change (e.g., you add a new `@export`), state_manager loads every resource of that class and calls `ResourceSaver.save()` on each one. This ensures the `.tres` files reflect the new schema. With hundreds of resources, this freezes the editor.

But this is the correct behavior for keeping resources in sync with their schema. The alternative (lazy migration) is more complex and introduces subtle bugs when old `.tres` files lack new properties.

**Effort: High to fix properly (lazy migration), and the current approach is correct.** Leave it unless users complain about the freeze.

### 9. `class_is_resource_descendant()` has no cycle guard

If the parent map somehow contains a cycle (A extends B, B extends A), this recurses forever. Godot's editor should prevent this, but defensive code would add a `visited` set. The risk is theoretical.

**Effort: Trivial, but the risk is near-zero.** Add it if you're bored.

### 10. `current_shared_propery_list` is misspelled

It's `propery` not `property`. This propagates through ResourceList, ResourceRow, HeaderRow, and StateManager. It's cosmetic but irritating.

**Effort: Low.** Global rename. But it touches many files and diffs will be noisy.

---

## Priority Ranking

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| **1** | Fix dialog wiring (dead signals, duplicate connections, silent errors) | Low | Fixes real bugs |
| **2** | Eliminate `_selected_paths` parallel state | Low | Prevents future bugs |
| **3** | Unify delete flows (per-row vs toolbar) | Medium | Fixes stale selection bug |
| **4** | Fix toolbar dangling reference (`tree_exiting`) | Trivial | Correctness |
| **5** | Make `ProjectClassScanner` map params required | Low-Medium | Performance correctness |
| **6** | Split StateManager into focused pieces | High | Testability, maintainability |
| **7** | Fix `propery` typo | Low | Cosmetic |

Items 1-4 are clear wins with low effort. Item 5 prevents accidental performance regressions. Item 6 is the big one that pays dividends long-term but is a significant investment. Item 7 is whenever you feel like it.

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
    ├─ Selection (selected_resources, _selected_paths, last_index)
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
    ├─ SaveResourceDialog ──listens──→ create_new_resource_requested (DUPLICATE)
    ├─ ConfirmDeleteDialog ──listens──→ delete_selected_requested
    └─ ErrorDialog ──listens──→ error_occurred
```

## Architecture Diagram (Proposed after StateManager split)

```
VREStateManager (thin coordinator, ~80 LOC)
  ├─ ClassRegistry        ← class maps, rename detection, descendant resolution
  ├─ ResourceRepository   ← resource loading, mtime tracking, change detection
  ├─ SelectionManager     ← shift/ctrl/none logic, selected_resources
  ├─ PaginationManager    ← page slicing, page-level diffs
  └─ FilesystemListener   ← EditorFileSystem signals, debounce, suppression

UI components unchanged — they still talk to VREStateManager.
VREStateManager delegates internally.
Each piece is independently testable with stubs.
```
