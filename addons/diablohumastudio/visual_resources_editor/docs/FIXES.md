# VRE Architecture — Fixes

Consolidated list from Claude, Codex, and Gemini analyses. Items that appear in multiple analyses are merged.

---

## Solved

### 1. God-Object `VREStateManager` (internal split)

**Proposed by:** Claude, Codex, Gemini
**Status:** Solved

**Problem:** `VREStateManager` handled class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic, filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and 12 signals — at least 6 distinct responsibilities in one file.

**Fix:** Split into focused `RefCounted` sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`). `VREStateManager` is now a thin coordinator (~170 LOC) that wires them together and exposes the same public API to UI.

---

### 2. VM-to-VM Dependency Hell (MVVM refactor)

**Proposed by:** Claude, Codex, Gemini
**Status:** Solved

**Problem:** Five ViewModels depended on `ClassSelector VM -> Selected Class` and three depended on `SubclassFilter VM -> Include Subclasses`, creating horizontal VM-to-VM coupling that is hard to test and violates MVVM's unidirectional dependency rule.

**Fix:** Introduced `SessionStateModel` in the Model layer to own all shared session state (`selected_class`, `include_subclasses`, `selected_resources`, `current_page`). All VMs read session state from `VREModel` (which exposes `SessionStateModel` internally). VM-to-VM dependencies are fully eliminated.

---

### 3. Full MVVM Layer Implementation

**Proposed by:** Claude
**Status:** Solved

**Problem:** All UI components held a reference to the full `VREStateManager` god object, binding directly to domain objects with no separation layer.

**Fix:** Implemented a complete ViewModel layer (`view_models/`). Each View now binds to a dedicated ViewModel. `VisualResourcesEditorWindow` creates all VMs and injects them. Key decisions:

- `SessionStateModel` (Model layer) eliminates VM-to-VM dependencies.
- `BulkEditor` connects directly to `VREModel` — it is a non-visual service, not a View, so no ViewModel is needed or useful.
- `ResourceRowVM` (per-row VM) simplifies `ResourceListVM` and removes the global selection sweep in `ResourceList`.

See `architecture_analisys.md` for full decision rationale.

---

## Pending

### 4. `VREStateManager` Is a Redundant Proxy

**Proposed by:** Gemini, Codex, Claude
**Severity:** Architectural Waste

**Problem:** `VREStateManager` is a 1:1 pass-through over `VREModel`. Every signal is re-emitted, every method delegates, every accessor reaches through to `_model`. The Window already pierces through it (`_state.model`) to inject VMs, so the facade is not even used as a facade. This creates a 5-layer call stack (View -> VM -> StateManager -> VREModel -> SubManager) where 4 would suffice.

**Fix:** Delete `VREStateManager`. Instantiate `VREModel` directly in `VisualResourcesEditorWindow`. Call `model.start()` / `model.stop()` there.

**References:**
- `core/state_manager.gd:5-124`
- `ui/visual_resources_editor_window.gd:8-21`

---

### 5. `VREModel` Is Still a God Object

**Proposed by:** Codex, Claude
**Severity:** High Change-Risk

**Problem:** The old god object was split into sub-managers, but all policy and orchestration logic stayed in `VREModel` (~400 LOC). It still owns: lifecycle wiring, session reaction handlers, class resolution, property scanning, rename detection, orphan cleanup, sort policy (~90 lines of sort/compare code), pagination reactions, and view reset. Adding a feature still means touching this one file.

**Fix:** Extract at minimum:
- Sort logic (static methods `_sort_resources`, `_sort_value`, `_compare_values`) into a `ResourceSorter` utility.
- Class resolution + property scanning (`_resolve_current_classes`, `_scan_current_properties`, `_handle_property_changes`) into a `ClassDomainService` or into `ClassRegistry` itself.
- Keep `VREModel` as a thin coordinator/facade that wires sub-managers and reacts to session changes.

**References:**
- `core/vre_model.gd:59-82` (lifecycle wiring)
- `core/vre_model.gd:120-159` (class resolution + property scanning)
- `core/vre_model.gd:174-278` (manager reactions + property change handling)
- `core/vre_model.gd:298-396` (sort logic)

---

### 6. ResourceRowVM Signal Leak / O(N*M) Selection Performance

**Proposed by:** Gemini, Codex, Claude
**Severity:** Memory Leak + Performance Bottleneck

**Problem:** Every `ResourceRowVM` connects to `VREModel.selection_changed`. Two compounding issues:

1. **Leak:** `ResourceRowVM` is `RefCounted`. When rows are replaced (page navigation, class change), old VMs are cleared from `ResourceListVM.rows`, but their signal connection to `VREModel` still exists — VREModel's signal keeps a reference to the callback closure, preventing the VM from being freed. Over many page navigations, hundreds of zombie VMs accumulate.

2. **Performance:** When selection changes, every row (including zombie rows) executes an O(M) `resources.has(resource)` lookup. With 50 visible rows and 100 selected items, that's 5,000 operations per selection event — and it grows with zombie count.

**Fix:**
- Remove per-row subscription to global selection state entirely.
- Let `ResourceListVM` compute selection deltas and push `is_selected` state into only the affected `ResourceRowVM`s.
- Use a `Dictionary[Resource, bool]` in `SelectionManager` for O(1) lookups.
- If keeping per-row subscriptions, add explicit `disconnect()` cleanup when rows are replaced.

**References:**
- `view_models/resource_row_vm.gd:10-30`
- `view_models/resource_list_vm.gd:19-64`

---

### 7. Disk-Spamming I/O in BulkEditor

**Proposed by:** Gemini
**Severity:** Reliability Risk

**Problem:** `BulkEditor._on_inspector_property_edited` calls `ResourceSaver.save()` immediately for every property change. Godot's `property_edited` signal fires on every keystroke in a `LineEdit` or every pixel moved in a `Slider`. This spams the filesystem with hundreds of writes per second, causing micro-stutters and risking file corruption on crash.

**Fix:** Implement debounced saving — only write after 500ms of inactivity. Or use a "commit on focus loss" / explicit "Save" button.

**References:**
- `core/bulk_editor.gd:86-108`

---

### 8. Persistence Ownership Split Across Classes

**Proposed by:** Codex, Claude
**Severity:** High-Risk Design Flaw

**Problem:** `ResourceRepository` owns resource loading and mtime tracking, but `BulkEditor` writes resources directly via `ResourceSaver.save()`, bypassing the repository. The component tracking file state is not the component mutating file state. Mtimes can drift, delta scans see phantom "modified" resources, and error handling is duplicated.

**Fix:** Centralize all save/write behind `ResourceRepository`:
- `resource_repo.save_resources(resources: Array[Resource]) -> Array[String]` (returns failed paths)
- `BulkEditor` calls the repository, which saves, updates mtimes, and reports errors in one place.

**References:**
- `core/bulk_editor.gd:86-108`
- `core/resource_repository.gd:28-67`
- `core/resource_repository.gd:70-79`

---

### 9. MVVM Violation: Domain Logic Leaks Into Views

**Proposed by:** Gemini, Codex, Claude
**Severity:** Architectural Debt

**Problem:** `ResourceRow.gd` (the View) calls `get_script().get_script_property_list()`, filters `PROPERTY_USAGE_EDITOR`, excludes `resource_*` / `metadata/*` / `script` properties, and decides which cells exist. This is schema/domain logic living in a Button scene. The same filtering logic already exists in `ProjectClassScanner.get_properties_from_script_path`.

**Fix:** Move property ownership computation into `ResourceRowVM`. The VM should provide a ready-to-render list of `{ name, value, type }` cell data. The View blindly renders whatever the VM gives it.

**References:**
- `ui/resource_list/resource_row.gd:22-49`

---

### 10. MVVM Violation: Delete I/O in View Layer

**Proposed by:** Claude
**Severity:** Architectural Debt

**Problem:** `ConfirmDeleteDialog.gd` (a View) directly calls `OS.move_to_trash()` and `EditorFileSystem.update_file()`. File I/O belongs in the Model layer, not in a dialog.

**Fix:** The dialog should call `vm.confirm_delete(paths)`. The VM (or a model-layer service) performs the actual deletion and error reporting.

**References:**
- `ui/dialogs/confirm_delete_dialog.gd:33-48`

---

### 11. "Caveman" Filesystem Scanning

**Proposed by:** Gemini
**Severity:** Performance Bottleneck

**Problem:** `ProjectClassScanner.get_class_from_tres_file` manually opens every `.tres` file to read the first line for `script_class`. This is O(N) disk I/O per scan. Godot's `EditorFileSystem` already maintains a metadata index.

**Fix:** Use `EditorFileSystem`'s API: `EditorFileSystemDirectory.get_file_script_class_name(idx)` for instant lookups instead of raw `FileAccess.open`.

**References:**
- `core/project_class_scanner.gd:105-115`

---

### 12. Type-Unsafe Property Merging

**Proposed by:** Gemini
**Severity:** Potential Data Corruption

**Problem:** `unite_classes_properties` merges properties by name only. If `ClassA.power: int` and `ClassB.power: String`, the editor picks the first type it finds and applies it to all. Writing a String into an int field via BulkEditor causes errors or data loss.

**Fix:** Detect type mismatches during union. Either:
1. Mark conflicting properties as "mixed type" and disable editing for them.
2. Only include properties where name AND type match exactly across all classes.

**References:**
- `core/project_class_scanner.gd:162-175`

---

### 13. ResourceFieldLabel Mutates Shared Theme Styles

**Proposed by:** Claude
**Severity:** Visual Bug

**Problem:** `ResourceFieldLabel.set_value()` calls `get_theme_stylebox("normal") as StyleBoxFlat` and modifies `.bg_color` directly. This returns a shared theme style — mutating it changes the background for ALL labels using that theme, not just the current one. Color-type fields visually corrupt other fields' backgrounds.

**Fix:** Create a per-instance `StyleBoxFlat` clone in `_ready()` via `add_theme_stylebox_override("normal", style.duplicate())` and mutate only that copy.

**References:**
- `ui/resource_list/resource_field_label.gd:11-16`

---

### 14. O(n^2) in ResourceRepository.scan_for_changes

**Proposed by:** Claude
**Severity:** Performance Bottleneck

**Problem:** `scan_for_changes` iterates `known_paths` (the mtime dictionary keys) and calls `current_paths.has(path)` for each, which is an O(n) array scan. With hundreds of resources, the full scan is O(n^2).

**Fix:** Convert `current_paths` to a `Dictionary[String, bool]` before the loop for O(1) lookups.

**References:**
- `core/resource_repository.gd:53-60`

---

### 15. ViewModels Are Mostly Decorative Wrappers

**Proposed by:** Codex, Claude
**Severity:** Architectural Debt

**Problem:** Most VMs are thin signal-forwarders with trivial getters. `SubclassFilterVM` (11 LOC), `ErrorDialogVM` (11 LOC), `PaginationBarVM` (27 LOC) add files and indirection without real isolation. They expose `model.session` internals directly, so the MVVM "contract" they provide is illusory.

**Fix:** Either:
- **Strengthen** VMs into real adapters that expose UI-shaped state and hide model internals. VREModel should expose query methods like `get_toolbar_state()`, `get_pagination_state()` instead of raw session access.
- **Delete** trivial VMs and let simple views bind to model signals directly, reserving VMs only for views with real presentation logic (ResourceList, Toolbar).

**References:**
- `view_models/subclass_filter_vm.gd`
- `view_models/error_dialog_vm.gd`
- `view_models/pagination_bar_vm.gd`
- `view_models/class_selector_vm.gd:10-23`
- `view_models/toolbar_vm.gd:9-42`

---

### 16. BulkEditor Multi-Select Proxy May Corrupt Data

**Proposed by:** Claude
**Severity:** Potential Data Corruption

**Problem:** When multiple resources with different scripts are selected, `_get_common_script()` falls back to `model.current_class_script` (the base class script). The proxy is then created from this base script with all default values. Editing any property writes the edited value to all selected resources — but properties not touched remain at defaults in the proxy, and if the user edits the same proxy again, the inspector may write those defaults to all resources too. Additionally, single-select mode only copies values from `current_class_property_list` / `current_included_class_property_lists`, potentially missing properties from the actual resource's specific subclass.

**Fix:** For multi-select with mixed scripts, either:
1. Only expose properties shared across all selected resources' actual scripts.
2. Disable editing entirely when scripts differ and show a warning.

**References:**
- `core/bulk_editor.gd:50-68`
- `core/bulk_editor.gd:78-84`

---

### 17. UI Node Thrashing (No Object Pooling)

**Proposed by:** Gemini
**Severity:** Performance Debt

**Problem:** `ResourceList` and `ResourceRow` use `queue_free()` and `instantiate()` to rebuild the entire UI on every page change or class switch. This causes frame drops and memory churn in the Godot Editor, especially with many columns.

**Fix:** Implement object pooling for `ResourceRow` and `ResourceFieldLabel`. Instead of destroying and recreating, hide unused nodes and update data in existing ones.

**References:**
- `ui/resource_list/resource_list.gd:43-47` (rows_replaced)
- `ui/resource_list/resource_list.gd:103-109` (clear_rows)
- `ui/resource_list/resource_row.gd:22-49` (build_field_labels)

---

## Minor / Cleanup

### 18. `ClassDefinition` Is Dead Code

**Proposed by:** Claude
**Severity:** Cleanup

**Problem:** `core/data_models/class_definition.gd` exists but is never referenced anywhere in the codebase. Leftover from an earlier design.

**Fix:** Delete `class_definition.gd` and its `.uid` sidecar.

**References:**
- `core/data_models/class_definition.gd`

---

### 19. `search_filter` Is Dead Infrastructure

**Proposed by:** Claude
**Severity:** Cleanup

**Problem:** `SessionStateModel` declares `search_filter: String` with a `search_filter_changed` signal, but nothing in the codebase connects to it or sets it. Ghost feature.

**Fix:** Remove `search_filter` and its signal from `SessionStateModel` until search is actually implemented.

**References:**
- `core/data_models/session_state_model.gd:7,27-30`

---

### 20. Typo in Public API

**Proposed by:** Claude
**Severity:** Cleanup

**Problem:** `request_create_new_resouce()` is missing an 'r' — should be `request_create_new_resource()`. Appears in `VREModel`, `VREStateManager`, and `ToolbarVM`.

**Fix:** Rename to `request_create_new_resource()` across all files.

**References:**
- `core/vre_model.gd:100-101`
- `core/state_manager.gd:103-104`
- `view_models/toolbar_vm.gd:33`

---

### 21. Duplicate Null Check in ProjectClassScanner

**Proposed by:** Claude
**Severity:** Cleanup

**Problem:** `scan_folder_for_classed_tres_paths` checks `dir == null or not is_instance_valid(dir)` twice — lines 80-81 and 84-85 are identical.

**Fix:** Remove the redundant second check.

**References:**
- `core/project_class_scanner.gd:80-86`

---

### 22. Unnecessary Lambdas in Signal Forwarding

**Proposed by:** Claude
**Severity:** Code Style (per CLAUDE.md convention)

**Problem:** Several VMs wrap signal connections in unnecessary lambdas:
```gdscript
_model.error_occurred.connect(func(msg: String): error_occurred.emit(msg))
```
Per CLAUDE.md convention, methods/signals are already Callables. The lambda captures nothing extra.

**Fix:** Use direct callable connection:
```gdscript
_model.error_occurred.connect(error_occurred.emit)
```

**References:**
- `view_models/error_dialog_vm.gd:10`
- `view_models/subclass_filter_vm.gd:10`
- `view_models/save_resource_dialog_vm.gd:11-12`
- `view_models/class_selector_vm.gd:12-14`

---

### 23. StatusLabelVM Tracks Count Manually

**Proposed by:** Claude
**Severity:** Fragility

**Problem:** `StatusLabelVM` maintains `_visible_count` by manually adding/subtracting from add/remove/replace signals. If signals fire out of order or are missed, the count silently drifts from reality. Same concern for `PaginationBarVM` caching `_total_pages`.

**Fix:** Query the count from the model when needed instead of maintaining a shadow counter. Or verify the counter against the model on each update.

**References:**
- `view_models/status_label_vm.gd:13-29`
- `view_models/pagination_bar_vm.gd:8,14-16`

---

### 24. `Dialogs.gd` Is a Pointless Indirection

**Proposed by:** Claude
**Severity:** Cleanup

**Problem:** `Dialogs` exists solely to forward VM assignments from the Window to its three child dialogs. The Window could assign VMs directly to `%SaveResourceDialog`, `%ConfirmDeleteDialog`, `%ErrorDialog` since they're all unique-name nodes in the same owner.

**Fix:** Delete `Dialogs.gd` and its `.tscn`. Move the three dialog nodes directly into `visual_resources_editor_window.tscn` as unique-name children. Assign VMs directly in Window's `_ready()`.

**References:**
- `ui/dialogs/dialogs.gd`
- `ui/dialogs/dialogs.tscn`
- `ui/visual_resources_editor_window.gd:17-19`
