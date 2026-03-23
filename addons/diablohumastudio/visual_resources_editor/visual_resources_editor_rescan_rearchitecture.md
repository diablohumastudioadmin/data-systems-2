# Visual Resources Editor — `rescan()` Rearchitecture Proposal

## Problem Statement

`VREStateManager.rescan()` is a monolithic function that always performs the full pipeline: resolve classes → scan properties → walk filesystem → restore selection → emit page data. Every caller triggers all steps regardless of what actually changed. This causes:

1. **Duplicate work** — `rescan()` builds a `class_to_path` dictionary by iterating `global_classes_map`, then `unite_classes_properties()` builds the exact same dictionary internally.
2. **No granularity** — `_handle_classes_updated()` sometimes only needs to refresh properties (not reload .tres files), but it calls full `rescan()`. `_on_filesystem_changed()` only needs to reload .tres files (not rebuild property lists), but also calls full `rescan()`.
3. **Always resets to page 0** — even when only a property changed or a single .tres was added/removed.
4. **Mixed responsibilities** — class resolution, property scanning, filesystem I/O, selection state, and pagination are interleaved in one function.

---

## Current `rescan()` Annotated

```gdscript
func rescan() -> void:
    # 1. GUARD
    if _current_class_name.is_empty(): return

    # 2. RESOLVE CLASSES
    current_class_names = _get_included_classes()
    if current_class_names.is_empty(): push_warning(...); return
    current_class_script = _get_class_script(_current_class_name)

    # 3. BUILD class_to_path  ← DUPLICATE of work inside unite_classes_properties
    var class_to_path: Dictionary = {}
    for entry in global_classes_map:
        class_to_path[entry.class] = entry.path

    # 4. LOAD PROPERTY LISTS per subclass
    subclasses_property_lists = {}
    for cls_name in current_class_names:
        subclasses_property_lists[cls_name] = get_properties_from_script_path(class_to_path[cls_name])
    current_class_property_list = subclasses_property_lists.get(_current_class_name, [])

    # 5. UNITE COLUMNS  ← rebuilds class_to_path again internally
    columns = ProjectClassScanner.unite_classes_properties(current_class_names, global_classes_map)

    # 6. SCAN FILESYSTEM for .tres files  ← most expensive step
    resources = ProjectClassScanner.load_classed_resources_from_dir(current_class_names, root)

    # 7. RESTORE SELECTION
    # ... match _selected_paths against new resources ...
    selection_changed.emit(...)

    # 8. RESET PAGINATION  ← always page 0
    _current_page = 0
    _emit_page_data()
```

---

## Proposed Decomposition

Break `rescan()` into 4 focused private methods. `rescan()` becomes a thin orchestrator that calls all of them.

### New private methods

```gdscript
## Resolves current_class_names and current_class_script from _current_class_name.
## Returns true if there are classes to display, false otherwise.
func _resolve_classes() -> bool:
    if _current_class_name.is_empty():
        return false
    current_class_names = _get_included_classes()
    if current_class_names.is_empty():
        push_warning("VREStateManager: class '%s' resolved to no classes. Was it deleted?" % _current_class_name)
        return false
    current_class_script = _get_class_script(_current_class_name)
    return true


## Rebuilds subclasses_property_lists, current_class_property_list, and columns
## from the current class set. Uses _class_to_path cache (see below).
func _scan_properties() -> void:
    subclasses_property_lists = {}
    for cls_name: String in current_class_names:
        var script_path: String = _class_to_path.get(cls_name, "")
        if not script_path.is_empty():
            subclasses_property_lists[cls_name] = ProjectClassScanner.get_properties_from_script_path(script_path)

    var empty_props: Array[Dictionary] = []
    current_class_property_list = subclasses_property_lists.get(_current_class_name, empty_props)

    # Unite all subclass properties into a single column list.
    # Pass _class_to_path so unite_classes_properties doesn't rebuild it.
    columns = _unite_columns()


## Walks the filesystem and loads all .tres resources matching current_class_names.
func _scan_resources() -> void:
    var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
    if root == null or not is_instance_valid(root):
        push_warning("VREStateManager: filesystem directory is not valid, skipping resource scan.")
        return
    resources = ProjectClassScanner.load_classed_resources_from_dir(current_class_names, root)


## Matches _selected_paths against the current resources list and emits selection_changed.
func _restore_selection() -> void:
    var prev_paths: Array[String] = _selected_paths.duplicate()
    selected_resources.clear()
    _selected_paths.clear()
    for res: Resource in resources:
        if prev_paths.has(res.resource_path):
            selected_resources.append(res)
            _selected_paths.append(res.resource_path)
    _last_anchor = resources.find(selected_resources.back()) if not selected_resources.is_empty() else -1
    selection_changed.emit(selected_resources.duplicate())
```

### New `rescan()` — thin orchestrator

```gdscript
func rescan() -> void:
    if not _resolve_classes():
        return
    _scan_properties()
    _scan_resources()
    _restore_selection()
    _current_page = 0
    _emit_page_data()
```

Identical behavior, zero logic changes — just decomposed.

### New cached member: `_class_to_path`

Add a member alongside the existing maps:

```gdscript
var _class_to_path: Dictionary[String, String] = {}
```

Update `_set_maps()` to build it once:

```gdscript
func _set_maps() -> void:
    global_classes_map = ProjectClassScanner.build_global_classes_map()
    _classes_parent_map = ProjectClassScanner.build_project_classes_parent_map(global_classes_map)

    _class_to_path.clear()
    for entry: Dictionary in global_classes_map:
        var cls: String = entry.get("class", "")
        var path: String = entry.get("path", "")
        if not cls.is_empty() and not path.is_empty():
            _class_to_path[cls] = path
```

Then `_scan_properties()` uses `_class_to_path` directly (no local rebuild), and `_unite_columns()` can also use it:

```gdscript
func _unite_columns() -> Array[Dictionary]:
    var properties: Array[Dictionary] = []
    for cls_name: String in current_class_names:
        var script_path: String = _class_to_path.get(cls_name, "")
        if script_path.is_empty():
            continue
        for prop: Dictionary in ProjectClassScanner.get_properties_from_script_path(script_path):
            if not properties.has(prop):
                properties.append(prop)
    return properties
```

This replaces the call to `ProjectClassScanner.unite_classes_properties()` and eliminates the second `class_to_path` build.

---

## Optimized `_handle_classes_updated()` — Granular Paths

With decomposed functions, `_handle_classes_updated` can now take cheaper paths:

```gdscript
func _handle_classes_updated() -> void:
    _classes_update_pending = false
    _set_maps()

    var previous_classes: Array[String] = project_resource_classes.duplicate()
    project_resource_classes = ProjectClassScanner.get_project_resource_classes(global_classes_map)

    # Re-save .tres files for classes that disappeared (handles renames)
    var removed_classes: Array[String] = []
    for cls: String in previous_classes:
        if not project_resource_classes.has(cls):
            removed_classes.append(cls)
    if not removed_classes.is_empty():
        var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
        if root != null and is_instance_valid(root):
            var resources_to_update: Array[Resource] = ProjectClassScanner.load_classed_resources_from_dir(removed_classes, root)
            for res: Resource in resources_to_update:
                ResourceSaver.save(res, res.resource_path)

    # ── Path A: Class list unchanged — only properties might have changed ──
    if previous_classes == project_resource_classes:
        if not _current_class_name.is_empty():
            var new_props: Array[Dictionary] = _get_current_class_props()
            if new_props != current_class_property_list:
                project_classes_changed.emit(project_resource_classes)
                # OPTIMIZATION: only rebuild properties + re-emit, skip filesystem walk
                _scan_properties()
                _emit_page_data()
        return

    # ── Path B: Class list changed — always update dropdown ──
    project_classes_changed.emit(project_resource_classes)

    if _current_class_name.is_empty():
        return

    # Current class was deleted/renamed — clear everything
    if not project_resource_classes.has(_current_class_name):
        _clear_view()
        return

    # Check if browsed subclasses were added/removed
    for cls: String in current_class_names:
        if not previous_classes.has(cls) or not project_resource_classes.has(cls):
            rescan()  # full rescan — class set changed
            return

    # Only properties changed within existing class set
    var new_props: Array[Dictionary] = _get_current_class_props()
    if new_props != current_class_property_list:
        # OPTIMIZATION: only rebuild properties + re-emit, skip filesystem walk
        _scan_properties()
        _emit_page_data()
```

### Key optimization: Path A skips `_scan_resources()`

When only `@export` properties changed (most common case during development), we no longer walk the entire project filesystem. The .tres files haven't changed — only the columns and property lists need rebuilding.

---

## Optimized `_on_filesystem_changed()` — Skip Property Rebuild

```gdscript
func _on_filesystem_changed() -> void:
    if _classes_update_pending:
        return
    # OPTIMIZATION: only rescan .tres files, skip property/class resolution
    %RescanDebounceTimer.start_debouncing(_rescan_resources_only)


func _rescan_resources_only() -> void:
    if _current_class_name.is_empty():
        return
    # Classes and properties haven't changed — only .tres files were added/removed/modified
    _scan_resources()
    _restore_selection()
    _emit_page_data()  # preserves _current_page (see pagination fix below)
```

This avoids calling `_resolve_classes()` and `_scan_properties()` when only .tres files changed.

---

## Pagination Preservation

Currently `rescan()` always resets `_current_page = 0`. With the decomposition we can be smarter:

```gdscript
## Full rescan (class change, user selection from dropdown) → reset to page 0
func rescan() -> void:
    if not _resolve_classes():
        return
    _scan_properties()
    _scan_resources()
    _restore_selection()
    _current_page = 0
    _emit_page_data()


## Partial rescan (filesystem change, property change) → preserve page if valid
func _emit_page_data_preserving_page() -> void:
    var max_page: int = _page_count() - 1
    if _current_page > max_page:
        _current_page = max_page
    _emit_page_data()
```

Use `_emit_page_data_preserving_page()` in the optimized paths where the user didn't change the class selection.

---

## Summary of Changes

| File | Change |
|------|--------|
| `state_manager.gd` | Extract `_resolve_classes()`, `_scan_properties()`, `_scan_resources()`, `_restore_selection()` from `rescan()` |
| `state_manager.gd` | Add `_class_to_path` member, populate in `_set_maps()` |
| `state_manager.gd` | Add `_unite_columns()` to replace `ProjectClassScanner.unite_classes_properties()` call (uses cached `_class_to_path`) |
| `state_manager.gd` | Add `_rescan_resources_only()` for filesystem_changed path |
| `state_manager.gd` | Add `_emit_page_data_preserving_page()` for partial rescans |
| `state_manager.gd` | Update `_handle_classes_updated()` to use granular paths |
| `state_manager.gd` | Update `_on_filesystem_changed()` to use `_rescan_resources_only` |

No changes to `ProjectClassScanner`, UI files, `BulkEditor`, or scene files.

---

## Call Graph After Rearchitecture

```
set_class() ──────────────────────→ rescan() (full, page 0)
set_include_subclasses() ─────────→ rescan() (full, page 0)
%RefreshBtn ──────────────────────→ rescan() (full, page 0)

_on_script_classes_updated()
  → debounce → _handle_classes_updated()
      ├─ class list unchanged, props changed
      │    → _scan_properties() + _emit_page_data_preserving_page()
      ├─ class list changed, subclasses changed
      │    → rescan() (full, page 0)
      ├─ class list changed, only props changed
      │    → _scan_properties() + _emit_page_data_preserving_page()
      └─ current class deleted
           → _clear_view()

_on_filesystem_changed()
  → debounce → _rescan_resources_only()
      → _scan_resources() + _restore_selection()
        + _emit_page_data_preserving_page()
```

Each path does only the minimum work required.
