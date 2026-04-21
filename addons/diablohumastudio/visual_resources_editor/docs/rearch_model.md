# Rearch Proposal: Scope-Owning Repository, No Session

---

## `script_classes_updated` reaction table

Trigger: `EditorFileSystem` fires `script_classes_updated`. RR calls `cr.rebuild()` then decides what to do.

| Map changed | Current class state | Props changed | Action |
|---|---|---|---|
| no  | unchanged | no  | nothing |
| no  | unchanged | yes | resave all + reload (CACHE_REPLACE) |
| yes | deleted   | —   | resave orphaned + clear `selected_class` |
| yes | renamed   | —   | resave orphaned + resave all (updates type field) + `selected_class = new_name` |
| yes | unchanged | no  | resave orphaned only |
| yes | unchanged | yes | resave orphaned + reload (CACHE_REPLACE) |

**"Map changed"** — RR compares `names` before and after `rebuild()`.  
**"Current class state"** — RR checks if `selected_class` is in the new list. If not, calls
`rcm.get_class_name_from_path(old_path)` with the path captured before `rebuild()`. Returns new name
(rename) or "" (deleted).  
**"Props changed"** — RR compares `get_properties(selected_class)` against `_current_class_props`.

---

## Change 1 — `ClassRegistry` → `ResourceClassMap`

### Naming

`ClassRegistry` implies a service. This is a passive data model: one computed store and derived lookups.

**New class name: `ResourceClassMap`**, file `resource_class_map.gd`.

Since the class name already says "ResourceClass", properties drop the redundant prefix:

| Old | New |
|---|---|
| `global_class_name_list` | `names` |
| `global_class_to_path_map` | `to_path` |
| `global_class_to_parent_map` | `to_parent` |
| `global_class_map` | _(removed — local only, see below)_ |
| `detect_rename` | `get_class_name_from_path` |
| `classes_changed` signal | `classes_changed` _(unchanged)_ |

### Filtering from the start

**Current problem**: `to_path` and `to_parent` are built from ALL project classes (Node, Control, etc.),
even though only Resource subclasses are ever queried. Filtering happens only at the end to produce
`names`. This means the maps have wasteful entries and wrong scope.

**Fix**: produce a filtered `Array[Dictionary]` of Resource-only entries first, then build all three
properties from that. The unfiltered raw map stays a local variable.

`rebuild()` calls one private entry-point `_resource_entries()` which reads ProjectSettings and
returns only Resource subclass entries. All derivative maps are built from that filtered slice.

```gdscript
# private — reads ProjectSettings, returns only Resource subclass entries
static func _resource_entries() -> Array[Dictionary]:
    var all: Array[Dictionary] = ProjectSettings.get_global_class_list()
    var all_to_parent: Dictionary[String, String] = _build_to_parent(all)   # full map needed for ancestry walk
    return all.filter(func(e: Dictionary) -> bool:
        var cls: String = e.get("class", "")
        var path: String = e.get("path", "")
        return not cls.is_empty() and not path.is_empty()
            and not path.contains("addons/")
            and _is_resource_descendant(cls, all_to_parent))

func rebuild() -> bool:
    var entries: Array[Dictionary] = _resource_entries()
    var previous: Array[String] = names.duplicate()
    names     = entries.map(func(e: Dictionary) -> String: return e.get("class", ""))
    to_path   = _build_to_path(entries)
    to_parent = _build_to_parent(entries)   # Resource-only, correct for get_included_classes
    var changed: bool = previous != names
    if changed:
        classes_changed.emit(previous, names)
    return changed
```

Note: `all_to_parent` (unfiltered) is needed inside `_resource_entries()` to correctly walk ancestry
chains that may pass through non-Resource intermediaries before reaching `Resource`. The stored `to_parent`
is then built from the already-filtered entries — this is fine because all user-defined bases of
Resource subclasses are themselves Resource subclasses, so the chain stays within the filtered set.

### Map-building helpers move into ResourceClassMap

**Current problem**: `ProjectClassScanner` lines 1–74 are static helpers that exist solely to build
the maps `ResourceClassMap` holds. They have no reason to live in a general-purpose scanner.

**Fix**: Move them into `ResourceClassMap` as private static helpers:

| Was in `ProjectClassScanner` | Becomes in `ResourceClassMap` |
|---|---|
| `build_global_classes_map()` | inlined as `ProjectSettings.get_global_class_list()` in `_resource_entries()` |
| `get_project_resource_classes()` | absorbed into `_resource_entries()` |
| `build_class_to_path_map()` | `_build_to_path()` private static |
| `build_project_classes_parent_map()` | `_build_to_parent()` private static |
| `class_is_resource_descendant()` | `_is_resource_descendant()` private static |
| `get_descendant_classes()` | `_get_descendants()` private static, called by `get_included_classes()` |

`ProjectClassScanner` keeps only its file/resource operations (lines 77–193):
`scan_folder_for_classed_tres_paths`, `get_class_from_tres_file`, `get_properties_from_script_path`,
`get_properties_from_script_names`, `get_properties_from_script_name`, `unite_classes_properties`,
`load_classed_resources_from_dir`.

---

## Change 2 — Rename detection moves from ClassSelectorVM to RR

**Current bug**: `ClassSelectorVM._on_classes_changed` calls `detect_rename` and sets
`_resource_repo.selected_class = new_name` directly, but never calls `resave_all()`. Resources on disk
keep the stale type string (old class name in `.tres` header). The fix only updates the UI.

**Fix**: Move rename detection into `RR._handle_class_update`. RR captures the old script path before
`rebuild()`, uses `get_class_name_from_path` after, and calls `resave_all()` + sets `selected_class`.

`ClassSelectorVM._on_classes_changed` becomes one line:
```gdscript
func _on_classes_changed(_previous: Array[String], current: Array[String]) -> void:
    browsable_classes_changed.emit(current)
```

`_selected_class_script_path` property removed from ClassSelectorVM — it was only needed for the rename
detection that now lives in RR.

---

## Change 3 — RR: single handler, no `classes_changed` subscription

RR does NOT subscribe to `classes_changed` from RCM (avoids re-entrancy: RCM emits synchronously
inside `rebuild()` which RR itself calls). RR captures before/after snapshots around `rebuild()`.

```gdscript
func _on_script_classes_updated() -> void:
    var previous: Array[String] = class_registry.names.duplicate()
    var old_path: String = class_registry.get_script_path(selected_class)  # capture before rebuild
    class_registry.rebuild()   # emits classes_changed for ClassSelectorVM; RR ignores it
    _handle_class_update(previous, class_registry.names, old_path)


func _handle_class_update(
        previous: Array[String], current: Array[String], old_path: String) -> void:
    var has_map_changed: bool = previous != current
    var is_current_class_missing: bool = has_map_changed and not current.has(selected_class)

    if has_map_changed:
        _resave_orphaned(previous, current)

    if is_current_class_missing:
        var new_name: String = class_registry.get_class_name_from_path(old_path)
        var is_current_class_renamed: bool = not new_name.is_empty()
        if is_current_class_renamed:
            _on_current_class_renamed(new_name)
        else:
            _on_current_class_deleted()
        return  # nothing else to check — current class is gone from the map

    if selected_class.is_empty():
        return

    var new_props: Array[ResourceProperty] = class_registry.get_properties(selected_class)
    var has_current_class_props_changed: bool = not ResourceProperty.arrays_equal(new_props, _current_class_props)

    if has_current_class_props_changed:
        _on_current_class_props_changed(new_props)


# rows 3 and 4 of the reaction table
func _on_current_class_renamed(new_name: String) -> void:
    resave_all()            # updates .tres type field to new class name
    selected_class = new_name   # setter triggers _reload()


func _on_current_class_deleted() -> void:
    selected_class = ""     # setter clears + emits resources_reset


# rows 2, 6 of the reaction table
func _on_current_class_props_changed(new_props: Array[ResourceProperty]) -> void:
    resave_all()
    _current_class_props = new_props.duplicate()
    _reload_fresh()
```

**Why no `else` after `if has_map_changed`**: `_resave_orphaned` runs on any map change. The
`if is_current_class_missing` block returns early, so everything below it runs only when the current
class is still present — whether or not the map changed. Both the "no map change" rows (1, 2) and the
"map changed, class unchanged" rows (5, 6) fall through to the props check. The `return` inside
`is_current_class_missing` is what makes the split explicit.

Remove `_on_classes_changed` from RR entirely. Rename `_last_known_props` → `_current_class_props`.

---

## Change 4 — `_reload_fresh()` helper

Schema-drift and post-rename reloads bypass Godot's resource cache (script changed, cached resource
may have stale property layout). Normal `_reload()` (class/subclass switch) does not need this.

```gdscript
func _reload_fresh() -> void:
    var included: Array[String] = class_registry.get_included_classes(selected_class, include_subclasses)
    current_class_resources = ProjectClassScanner.load_classed_resources_from_dir(included)
    # load_classed_resources_from_dir already uses CACHE_MODE_REPLACE internally
    _rebuild_mtimes()
    resources_reset.emit(current_class_resources.duplicate())
```

(Checking: `load_classed_resources_from_dir` line 190 already calls `CACHE_MODE_REPLACE` — no extra
flag needed.)

---

## Full file change list

| File | Change |
|---|---|
| `class_registry.gd` → `resource_class_map.gd` | Rename class. New property names (`names`, `to_path`, `to_parent`). Absorb map-building helpers from PCS. `_resource_entries()` filters from the start. `detect_rename` → `get_class_name_from_path`. Drop `classes_changed` subscription (it has none — stays passive). |
| `project_class_scanner.gd` | Delete lines 1–74 (map-building helpers). Keep lines 77–193 (file/resource ops). |
| `resource_repository.gd` | Drop `classes_changed` subscription. Replace two handlers with `_on_script_classes_updated` + `_handle_class_update`. Rename `_last_known_props` → `_current_class_props`. Add `_reload_fresh()`. Update all `class_registry.*` property references to new names. |
| `class_selector_vm.gd` | Remove `_selected_class_script_path`. Simplify `_on_classes_changed` to one line. Update type references. |
| All other callers of old property names | Update to `names` / `to_path` / `to_parent`. |

**Scope**: medium — logic changes are contained (RR, ClassSelectorVM), the rename + PCS split touches
more files but is mostly mechanical.

---

## What does NOT change

- FSL stays internal to RR. Not injected.
- `classes_changed` signal stays on RCM for ClassSelectorVM.
- `_reload()` (normal class/subclass switch) unchanged.
- `resave_all()` and `_resave_orphaned()` unchanged.
