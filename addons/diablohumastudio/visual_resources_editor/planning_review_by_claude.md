# Planning Review — Visual Resources Editor

This is a review of `visual_resources_editor_planning.md`. For each item I'll tell you: is the problem real given the actual code, and is the proposed solution any good?

---

## Current Architecture Diagrams

### Scene / Node Structure

> **Decided:** `ResourceCRUD` is removed. Dialog `.tscn` scenes replaced with script-only `.gd` files extending the base type. Each dialog self-wires its signals in `_ready()` and owns its own logic. Nodes are typed in `window.tscn` with scripts assigned.
>
> **Resolved:** All sibling `%` coupling removed. Dialogs and BulkEditor emit `error_occurred(message)` signals; window connects them to `%ErrorDialog.show_error`. BulkEditor also emits `resources_edited(resources)` — window receives it and calls `%ResourceList.refresh_row()` for each edited resource.

```
EditorPlugin (visual_resources_editor_plugin.gd)
└── adds menu via MainToolbarPlugin
    └── VisualResourcesEditorToolbar  (visual_resources_editor_toolbar.gd)
        └── [on menu click] instantiates ─►
            VisualResourcesEditorWindow  (window.tscn + window.gd)  ← orchestrator
            ├── MarginContainer
            │   └── VBoxContainer
            │       ├── TopBar
            │       │   ├── %ClassSelector          (class_selector.tscn + .gd)
            │       │   │   └── OptionButton
            │       │   └── %IncludeSubclassesCheck (CheckBox)
            │       └── %ResourceList               (resource_list.tscn + .gd)
            │           ├── Toolbar
            │           │   ├── CreateBtn
            │           │   ├── DeleteSelectedBtn
            │           │   └── RefreshBtn
            │           ├── %HeaderRow              (header_row.tscn + .gd)
            │           └── ScrollContainer
            │               └── %RowsContainer
            │                   ├── ResourceRow     (resource_row.tscn + .gd)  × N
            │                   ├── ResourceRow
            │                   └── ...
            ├── %VREStateManager        (state_manager.tscn + .gd)
            │   └── %RescanDebounceTimer  (Timer, 0.1s)
            ├── %BulkEditor             (Node, bulk_editor.gd, in window.tscn)
            ├── %SaveResourceDialog     (EditorFileDialog + save_resource_dialog.gd)
            ├── %ConfirmDeleteDialog    (ConfirmationDialog + confirm_delete_dialog.gd)
            └── %ErrorDialog            (AcceptDialog + error_dialog.gd)
```

---

### Data Flow: Selecting a Class

```
User picks class in dropdown
        │
        ▼
  ClassSelector
  emits class_selected(name)
        │
        ▼
  Window._on_class_selected()
  ├── StateManager.set_class(name)
  ├── BulkEditor.current_class_name = name
  └── SaveResourceDialog.current_class_name = name
        │
        ▼
  StateManager.rescan()
  ├── ProjectClassScanner.build_parent_map()       ← reads ProjectSettings
  ├── ProjectClassScanner.get_descendant_classes() ← if include_subclasses
  ├── ProjectClassScanner.scan_folder_for_classed_tres()
  │       └── for each .tres → ResourceLoader.load() ← loads every file ⚠️ (issue #1)
  └── _compute_union_columns()
          └── get_properties_from_script_path()    ← loads each .gd script
        │
        ▼
  StateManager emits data_changed(resources: Array[Resource], columns)
        │
        ▼
  Window._on_state_data_changed()
  ├── ClassSelector.set_classes_in_dropdown()
  └── ResourceList.set_data(resources, columns)
          └── destroys all rows, rebuilds from scratch ⚠️ (issue #2)
```

---

### Data Flow: Editing a Resource (Current)

```
User selects one or more ResourceRows
        │
        ▼
  ResourceList emits rows_selected(resources)
        │
        ▼
  Window._on_rows_selected()
  └── BulkEditor.edited_resources = [res, ...]
        │
        ▼
  BulkEditor (setter)
  ├── creates a proxy Resource  ← copy of first selected resource
  └── EditorInterface.edit_resource(proxy)  ← pushes proxy into Godot's Inspector panel
        │
        ▼
  User edits a field in the Inspector
        │
        ▼
  EditorInspector emits property_edited(prop_name)
        │
        ▼
  BulkEditor._on_inspector_property_edited()
  ├── reads new value from proxy
  ├── applies it to every resource in edited_resources
  ├── ResourceSaver.save(resource)  for each
  ├── emits error_occurred(msg) if any save failed
  └── emits resources_edited(edited_resources)
        │
        ▼
  Window._on_resources_edited(resources)
  └── ResourceList.refresh_row(path) for each  ← targeted update, no full rebuild

  [meanwhile, save() still triggers filesystem_changed → rescan ⚠️ (issue #5)]
```

---

### Data Flow: Create / Delete

> **New design:** `ResourceCRUD` is gone. `Window.gd` handles both operations directly, configuring the relevant dialog just before `.popup()`.

```
  ResourceList
  ├── CreateBtn pressed  →  emits create_requested
  │       │
  │       ▼
  │   Window._on_create_requested()
  │   ├── configures %SaveResourceDialog (filters, title, current path)
  │   └── %SaveResourceDialog.popup()
  │           │  (user picks save path and confirms)
  │           ▼
  │       Window._on_save_dialog_confirmed(path)
  │       ├── _get_class_script_path()  (ProjectSettings lookup)
  │       ├── script.new()  (instantiate resource)
  │       └── ResourceSaver.save()  → triggers filesystem_changed → rescan
  │
  └── DeleteSelectedBtn pressed  →  emits delete_requested(paths)
          │
          ▼
      Window._on_delete_requested(paths)
      ├── configures %ConfirmDeleteDialog (message with count/names)
      └── %ConfirmDeleteDialog.popup()
              │  (user confirms)
              ▼
          Window._on_delete_confirmed()
          ├── DirAccess.remove()  for each path
          └── EditorInterface.get_resource_filesystem().scan()  → triggers rescan

  [on any error in either flow]
      Window._show_error(msg)
      └── %ErrorDialog.dialog_text = msg  →  %ErrorDialog.popup()
```

---

### Component Responsibilities (What each file actually owns)

```
┌──────────────────────────┬──────────────────────────────────────────────────┐
│ File                     │ Responsibility                                   │
├──────────────────────────┼──────────────────────────────────────────────────┤
│ plugin.gd                │ EditorPlugin lifecycle, wires toolbar menu       │
│ toolbar.gd               │ Lazy-creates the Window on first menu click      │
│ window.gd                │ Orchestrator — connects signals, sets properties │
│ state_manager.gd         │ Holds class filter + subclass flag; triggers scan│
│                          │ Owns debounce timer for filesystem_changed       │
│ project_class_scanner.gd │ Static utilities: find .tres files, read props   │
│ save_resource_dialog.gd  │ Extends EditorFileDialog; owns create logic      │
│ confirm_delete_dialog.gd │ Extends ConfirmationDialog; owns delete logic    │
│ error_dialog.gd          │ Extends AcceptDialog; show_error(msg)            │
│ bulk_editor.gd           │ Proxy-based multi-resource Inspector editing     │
│ class_selector.gd        │ Dropdown UI — emits selected class name          │
│ resource_list.gd         │ Builds rows, handles selection, emits intents    │
│ resource_row.gd          │ Display-only row: labels per column + delete btn │
│ header_row.gd            │ Display-only header matching row column layout   │
└──────────────────────────┴──────────────────────────────────────────────────┘
```

---

## 1. State Manager Rescan (Eager Loading Trap)

**Is the problem real? Yes.**

`state_manager.gd` emits `data_changed(resources: Array[Resource], ...)`, which means it loads every `.tres` file into memory on every rescan. `ProjectClassScanner.get_class_from_tres_file()` also loads each `.tres` just to read its script class. This is genuinely expensive at scale.

**Is the solution good? Mostly, but it's incomplete.**

Changing the signal to pass `Array[String]` (paths) instead of loaded `Array[Resource]` is the right call. The problem is the proposed `_get_resource_paths()` still calls `scan_folder_for_classed_tres()`, which internally calls `get_class_from_tres_file()` — which still loads every `.tres`. The plan says "this needs to be optimized, see section 4/6", but section 4 only caches script property parsing, and section 6 is an architectural proposal. Nobody actually fixes the scanner's per-file loading. A real fix here would need a different approach, like reading the `.tres` file header as text (the `uid=` and `script` lines are at the top) to identify the class without a full `ResourceLoader.load()`.

**Verdict:** Problem is real. Solution is directionally correct but leaves the most expensive part (the scanner) unresolved.

---

## 2. UI Scalability (Virtual Scrolling)

**Is the problem real? At scale, yes. Right now, probably not urgent.**

Instantiating a `ResourceRow` scene per resource in a `VBoxContainer` does not scale to thousands of items. Godot's layout system has to measure and position every node, even off-screen ones. This is a genuine concern.

However: this is a game project editor tool. If you realistically expect 50–300 resources of any given class, the current approach is fine. The concern becomes real only if you regularly work with 1000+ items of the same class.

**Is the solution good? The concept is valid; the implementation has bugs.**

Virtual scrolling (pool a fixed number of rows, rebind data as the user scrolls) is the correct pattern. But the proposed code has issues:

- **`_process()` is wrong here.** Calling `_update_visible_items()` every frame is very expensive — it runs even when the user is not scrolling. The correct hook is `scroll_vertical`'s setter or connecting to the `scrolling` signal / `ScrollContainer`'s scroll changed notification.
- **Fixed `item_height = 32.0` is fragile.** Resource rows may not all be the same height. If they ever vary (more columns, wrapped text), the math breaks and rows misalign.
- **Selection state gets complicated.** Rows are recycled, so a selected row's visual state needs to be re-applied every time the row is rebound to new data. The proposed code doesn't handle this.

**Verdict:** Concern is real at scale, but premature for most game projects. Implement only when you actually hit the lag. The proposed implementation needs significant fixes before it works correctly.

---

## 3. Undo/Redo Integration

Skipped by request. Nothing to review.

---

## 4. Cache Properties (Severe I/O Abuse)

**Is the problem real? Partially.**

`_compute_union_columns()` calls `get_properties_from_script_path()` on every rescan. Loading a `.gd` script via `load()` on every scan is wasteful. However, "severe I/O abuse" is a bit dramatic — Godot's internal `ResourceLoader` caches scripts after the first load, so subsequent `load()` calls on the same path are fast cache hits. The `ProjectSettings.get_global_class_list()` call is also just a dictionary lookup, not disk I/O.

Real impact: mostly affects the very first scan after the plugin opens, not every subsequent rescan.

**Is the solution good? Good concept, but missing cache invalidation.**

Adding `static var _cached_script_properties: Dictionary` is sensible. But the cache has no way to know when a `.gd` file changes. If a user edits a schema script (adds a field, removes one), the cached properties are now stale and the editor will show wrong columns until `clear_cache()` is called manually — or the plugin is reloaded. The fix should listen to `EditorFileSystem.filesystem_changed` for `.gd` files and invalidate only the affected cache entries, not the entire cache.

**Verdict:** Concern is real but overstated. Solution is good in spirit but would ship with a silent stale-data bug.

---

## 5. Why the Current Debounce Is Flawed

**Is the problem real? Yes, this is the most real and urgent problem on this list.**

The sequence is accurate and reproducible right now:
1. User edits a resource property via the Inspector.
2. `BulkEditor` or `ResourceCRUD` calls `ResourceSaver.save()`.
3. Godot fires `EditorFileSystem.filesystem_changed`.
4. The debounce timer starts.
5. After 0.1 seconds, `rescan()` runs, rebuilding the entire list.
6. User loses scroll position, selection, and input focus.

You can observe this today without any load-testing.

**Is the solution good? Good, but the boolean flag has a timing risk.**

The `_is_saving_internally` flag approach is correct in principle. The risk: `filesystem_changed` is an async signal — it does not fire synchronously inside `ResourceSaver.save()`. It fires later (on the next editor filesystem poll). If `ResourceCRUD` calls `resume_rescans()` before that event arrives, the flag is already `false` and the rescan fires anyway.

A more robust approach is a **counter** instead of a boolean (`_pending_internal_saves: int`), incremented before save and decremented in a deferred call after save. Or, set `_is_saving_internally = true`, call `ResourceSaver.save()`, then call `resume_rescans.call_deferred()` (or after a short timer) so the flag stays up long enough to catch the async event.

**Verdict:** Problem is real and affects usability today. Solution is correct direction; just needs the async timing handled more carefully.

---

## 6. Improved Architecture (MVC Enforcement)

**Is the problem real? Somewhat.**

`BulkEditor` is genuinely convoluted — it creates a proxy resource, pushes it to the inspector, then listens to `EditorInspector.property_edited` to extract the change and apply it back to the real resources. It works but is hard to follow and fragile. The concern is valid.

**Is the solution good? The proposed solution changes more scope than it admits.**

The plan proposes that `ResourceRow` emits `intent_edit_property(resource_path, "health", 50)` when the user types a value. But looking at the actual `resource_row.gd` and `resource_row.tscn`: rows are **display-only**. They show Label nodes with field values — there are no editable fields in the rows. Editing is done via Godot's native Inspector panel (the `BulkEditor` selects the proxy resource and the Inspector shows it).

So the proposed MVC flow isn't just a refactor — it's proposing adding **inline row editing** (TextEdit/SpinBox per cell), which is a much bigger feature. That may or may not be what you want.

If you want to keep Inspector-based editing (the current UX), the simpler MVC fix is: have `BulkEditor` call `StateManager.pause_rescans()` before saving and `StateManager.resume_rescans()` after (per issue #5), and emit a targeted `single_item_updated(path)` signal instead of a full rescan. That's a much smaller change and gets you 90% of the benefit.

**Verdict:** The concern is real. The solution proposes a scope increase you may not have intended. A simpler targeted fix exists without adding inline editing.

---

## 7. Data Filtering Solution

**Is the problem real? It's a future concern, not a current bug.**

There is currently no search/filter UI in the plugin. No `SearchBar` node, no `set_filter_query()` method, nothing. So the "filtering by hiding nodes lags with thousands of rows" concern is about a feature that doesn't exist yet.

**Is the solution good? Yes, this is the right design to build the feature with.**

When you do add filtering, doing it at the data level in `StateManager` (filter `_all_paths` into `_filtered_paths`, emit to UI) is exactly right. The proposed code is clean and correct. It also pairs well with the virtual scrolling from #2 — the virtual scroll only sees the filtered list.

**Verdict:** Not a real current problem, but good forward planning. The solution is sound. Implement this when you add the filter UI.

---

## Summary

| # | Problem is real? | Solution is good? |
|---|---|---|
| 1 | Yes | Directionally correct, but doesn't fully fix the scanner's per-file loading |
| 2 | Only at 1000+ resources | Concept valid; `_process()` hook and fixed height are bugs |
| 3 | N/A | N/A |
| 4 | Partially (overstated) | Missing cache invalidation when `.gd` files change |
| 5 | **Yes, urgent today** | Correct approach; boolean flag has async timing risk |
| 6 | Somewhat | Proposes inline editing (bigger scope) — simpler fix exists |
| 7 | Not yet (future feature) | Good design for when you build it |

**What to actually do first:** Fix #5 (debounce/self-rescan loop). It's reproducible today, it directly breaks editing UX, and the fix is small. Everything else is optimization or future feature work.
