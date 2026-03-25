# Visual Resources Editor — MVVM Proposal (v3)

> Revised 2026-03-24.

---

## The Problems We're Solving

1. **Window is a routing hub** — `connect_components()` wires ~15 signals between components that don't know about each other. Every feature means more wiring in the window.
2. **State duplication** — `BulkEditor` holds copies of `current_class_script`, `current_class_property_list`, `subclasses_property_lists` that Window must manually sync from `VREStateManager` on every class change.
3. **VREStateManager is too big (~390 lines)** — it mixes data concerns (filesystem reactions, class scanning, resource cache, mtime tracking) with UI concerns (selection, pagination, page slicing).
4. **I/O scattered across components** — `BulkEditor` calls `ResourceSaver`, `ConfirmDeleteDialog` calls `OS.move_to_trash()`, `SaveResourceDialog` creates resources. Hard to reason about who does file I/O.

---

## MVVM Layers

### Model — `VREDataService`

The **data layer**. Reacts to filesystem events, scans classes and resources, caches results. No knowledge of selection, pagination, or UI. This is what `ProjectClassScanner` already does as static utilities — `VREDataService` wraps those utilities with lifecycle management and caching.

**Responsibilities:**
- Connect to `EditorFileSystem.filesystem_changed` and `script_classes_updated`
- Own the debounce timer for filesystem events
- Own `global_classes_map`, `class_to_path_map`, `_classes_parent_map`
- Own `project_resource_classes` (the list of available Resource classes)
- Scan resources for a given class set (full scan + mtime-based incremental)
- Own `_known_resource_mtimes` cache
- Detect class renames, orphaned resources, property changes
- Emit signals when data changes (classes changed, resources changed, etc.)

**Does NOT own:** selection, pagination, bulk edit proxy, inspector interaction.

**Extends:** `Node` (needs to own the debounce timer as a child, needs `_ready`/`_exit_tree` for EditorFileSystem signal lifecycle)

**Signals:**
- `project_classes_changed(classes: Array[String])`
- `resources_changed(resources: Array[Resource], columns: Array[ResourceProperty])`
- `resources_modified(changed_paths: Array[String])` — mtime-detected changes, no structural change
- `class_renamed(new_name: String)`
- `error_raised(message: String)`

**Public methods (called by ViewModel):**
- `initialize()`
- `set_class(class_name_str: String)`
- `set_include_subclasses(value: bool)`
- `refresh()`
- `get_class_script(class_name_str: String) -> GDScript`
- `get_subclasses_property_lists() -> Dictionary`
- `get_current_class_property_list() -> Array[ResourceProperty]`

**Comes from:** The data/scanning half of current `state_manager.gd` — specifically: `_set_maps()`, `_resolve_current_classes()`, `_scan_properties()`, `_scan_resources()`, `_rescan_resources_only()`, `_rebuild_known_mtimes()`, `_handle_classes_updated()`, `_handle_property_changes()`, `_resave_orphaned_resources()`, `_detect_class_rename()`, and the `_on_filesystem_changed`/`_on_script_classes_updated` handlers.

### ViewModel — `VREViewModel`

The **UI state layer**. Holds everything views need to render: selection, pagination, bulk edit proxy. Listens to the Model for data changes. Exposes commands that views call.

**Responsibilities:**
- Own selection state: `selected_resources`, `_selected_paths`, `_last_anchor`
- Own pagination: `_current_page`, `PAGE_SIZE`, page slicing
- Own bulk edit: `bulk_proxy`, `edited_resources`, proxy creation/cleanup
- Apply bulk edits (write values to selected resources, save via `ResourceSaver`)
- Listen to `VREDataService` signals → update selection (prune stale), re-emit page slices

**Does NOT own:** filesystem scanning, class maps, mtime cache, editor signal connections.

**Extends:** `Node` (owns `VREDataService` as a child node, simple and natural)

**Signals:**
- `page_data_changed(resources: Array[Resource], columns: Array[ResourceProperty])`
- `selection_changed(resources: Array[Resource])`
- `pagination_changed(page: int, page_count: int)`
- `bulk_proxy_changed(proxy: Resource)`
- `classes_changed(classes: Array[String])`
- `class_renamed(new_name: String)`
- `error_raised(message: String)`
- `rows_modified(paths: Array[String])`

**Public commands (called by views):**
- `initialize()`
- `select_class(class_name_str: String)`
- `set_include_subclasses(value: bool)`
- `select(resource: Resource, ctrl_held: bool, shift_held: bool)`
- `next_page()` / `prev_page()`
- `apply_bulk_edit(property: String)`
- `refresh()`

**Comes from:** The UI-state half of current `state_manager.gd` — specifically: `select()`, `next_page()`, `prev_page()`, `_restore_selection()`, `_emit_page_data()`, `_emit_page_data_preserving_page()`, `_clear_view()`. Plus all of `bulk_editor.gd`: `_create_bulk_proxy()`, `_clear_bulk_proxy()`, `_get_common_script()`, `_on_inspector_property_edited()`.

### Views — Existing UI Components

Views receive `vm` and wire themselves. Each view connects to the signals it cares about in its own `_set_vm()` setter. **Window does not route signals between vm and views.**

**How views get `vm`:** Window sets `vm` on each view in `_ready()`. Views connect to vm signals in their setter.

**Window's only remaining jobs:**
1. Create `VREViewModel` (or reference it as a scene child `%VREViewModel`)
2. Pass `vm` to views
3. Bridge `EditorInspector.property_edited` → `vm.apply_bulk_edit()` (inspector is a Window-level concern — it's not a data source, it's the user editing the bulk proxy)
4. Bridge `vm.bulk_proxy_changed` → `EditorInterface.inspect_object()` (pushing objects to the inspector is a Window-level side effect)
5. Own dialogs and pass them `vm` references for create/delete operations
6. Handle window-level input (ESC to close)

---

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────────────┐
│                    Window (host, minimal)                           │
│   creates vm, passes to views, bridges inspector                   │
│   owns dialogs                                                     │
└──┬──────────┬──────────────┬──────────────┬───────────────────────┘
   │          │              │              │
   ▼          ▼              ▼              ▼
ClassSel   ResourceList    Dialogs      %VREViewModel (Node)
(View)     (View)          (View)       ┌────────────────────────┐
                                        │ selection, pagination,  │
holds vm   holds vm                     │ bulk proxy, page slice  │
wires      wires                        │                         │
itself     itself                       │ commands: select(),     │
                                        │ next_page(), apply_     │
                                        │ bulk_edit()...          │
                                        │                         │
                                        │ listens to DataService  │
                                        │ re-emits for views      │
                                        └────────┬───────────────┘
                                                 │ owns
                                                 ▼
                                        ┌────────────────────────┐
                                        │ %VREDataService (Node)  │
                                        │                         │
                                        │ EditorFileSystem signals│
                                        │ debounce timer          │
                                        │ class scanning          │
                                        │ resource scanning       │
                                        │ mtime cache             │
                                        │ orphan detection        │
                                        │                         │
                                        │ uses ProjectClassScanner│
                                        │ (static utility)        │
                                        └─────────────────────────┘
```

**Signal flow:** `EditorFileSystem` → `VREDataService` → `VREViewModel` → Views. No view-to-view communication. Window only bridges inspector interactions.

---

## How Views Wire Themselves

Views that receive `vm` connect to its signals in their setter. This eliminates most of Window's routing role.

### ClassSelector

```gdscript
var vm: VREViewModel: set = _set_vm

func _set_vm(value: VREViewModel) -> void:
    vm = value
    if vm:
        vm.classes_changed.connect(_on_classes_changed)
        vm.class_renamed.connect(select_class)
```

Calls `vm.select_class()` when user picks from dropdown. Listens to `vm.classes_changed` to rebuild dropdown.

### ResourceList

```gdscript
var vm: VREViewModel: set = _set_vm

func _set_vm(value: VREViewModel) -> void:
    vm = value
    if vm:
        vm.page_data_changed.connect(set_data)
        vm.selection_changed.connect(update_selection)
        vm.pagination_changed.connect(update_pagination_bar)
        vm.rows_modified.connect(_on_rows_modified)

func _on_resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool) -> void:
    vm.select(resource, ctrl_held, shift_held)

func _on_rows_modified(paths: Array[String]) -> void:
    for path: String in paths:
        refresh_row(path)
```

Calls `vm.select()`, `vm.next_page()`, `vm.prev_page()`, `vm.refresh()` directly. No more emitting `row_clicked`, `prev_page_requested`, etc. through Window.

### Window (minimal)

```gdscript
func _ready() -> void:
    if not Engine.is_editor_hint(): return

    # Pass ViewModel to views — they wire themselves
    %ClassSelector.vm = %VREViewModel
    %ResourceList.vm = %VREViewModel

    # Inspector bridge (Window-level concern)
    %VREViewModel.bulk_proxy_changed.connect(_on_bulk_proxy_changed)
    %VREViewModel.error_raised.connect(error_dialog.show_error)

    var inspector: EditorInspector = EditorInterface.get_inspector()
    if inspector:
        inspector.property_edited.connect(_on_inspector_property_edited)

    # IncludeSubclasses checkbox (lives in Window scene, not in a view)
    %IncludeSubclassesCheck.toggled.connect(_on_include_subclasses_toggled)

    # Dialogs
    # ... (create/delete dialogs, pass vm or wire signals)

    %VREViewModel.initialize()

func _on_bulk_proxy_changed(proxy: Resource) -> void:
    if proxy:
        EditorInterface.inspect_object(proxy)
    else:
        EditorInterface.inspect_object(null)

func _on_inspector_property_edited(property: String) -> void:
    var inspector: EditorInspector = EditorInterface.get_inspector()
    if inspector and %VREViewModel.bulk_proxy and inspector.get_edited_object() == %VREViewModel.bulk_proxy:
        %VREViewModel.apply_bulk_edit(property)

func _on_include_subclasses_toggled(pressed: bool) -> void:
    %VREViewModel.set_include_subclasses(pressed)
    %SubclassWarningLabel.visible = pressed
```

**What Window no longer does:** route `row_clicked`, `create_requested`, `delete_requested`, `refresh_requested`, `prev_page_requested`, `next_page_requested`, `data_changed`, `selection_changed`, `pagination_changed`, `classes_changed`, `class_renamed`. All of these are now wired directly between views and vm.

---

## Size Comparison

Current `state_manager.gd` is ~390 lines doing everything. The split:

- **`VREDataService`** (~200 lines) — scanning, caching, filesystem reactions, orphan handling, class rename detection
- **`VREViewModel`** (~200 lines) — selection, pagination, bulk edit proxy, commands that delegate to DataService, signal re-emission for views

Neither component is a god object. Each has a clear single concern.

---

## File Changes

**New files:**
- `core/vre_data_service.gd` — Model layer (scanning, caching, filesystem)
- `core/vre_view_model.gd` — ViewModel (selection, pagination, bulk edit, view-facing signals)
- `core/vre_view_model.tscn` — Scene with VREViewModel as root, VREDataService + DebounceTimer as children

**Deleted files:**
- `core/state_manager.gd` — split into DataService + ViewModel
- `core/state_manager.tscn` — replaced by vre_view_model.tscn
- `core/bulk_editor.gd` — absorbed into ViewModel

**Modified files:**
- `ui/visual_resources_editor_window.gd` — thin shell, just passes vm to views + inspector bridge
- `ui/visual_resources_editor_window.tscn` — replace StateManager+BulkEditor nodes with VREViewModel scene instance
- `ui/class_selector/class_selector.gd` — add `vm` setter, wire itself
- `ui/resource_list/resource_list.gd` — add `vm` setter, wire itself, remove outward signals that Window was routing

**Unchanged files:**
All other files (views, scenes, dialogs, data models, scanner, plugin, toolbar).

---

## Migration Strategy

### Phase 1: Create DataService + ViewModel (non-breaking)

1. Create `core/vre_data_service.gd` with scanning/caching logic from state_manager.gd
2. Create `core/vre_view_model.gd` with selection/pagination/bulk-edit logic
3. Create `core/vre_view_model.tscn` (VREViewModel root + VREDataService child + DebounceTimer child)
4. Test: instantiate the scene, verify scanning and selection work

### Phase 2: Wire views to ViewModel

1. Add `vm` setter to ClassSelector and ResourceList
2. Window creates/references VREViewModel, passes to views
3. Views wire themselves via setter
4. Old StateManager + BulkEditor still in scene but unused
5. Test: plugin works identically

### Phase 3: Remove old code

1. Delete state_manager.gd, state_manager.tscn, bulk_editor.gd
2. Remove their nodes from window.tscn
3. Test: plugin works identically

Each phase is one commit. Plugin works at every step.

---

## Data Flow Examples

### Class Selection

```
User clicks ClassDropdown
  → ClassSelector calls vm.select_class("Weapon")
    → vm calls data_service.set_class("Weapon")
      → data_service scans resources + properties
      → data_service emits resources_changed(resources, columns)
    → vm receives resources_changed
      → vm restores selection, computes page slice
      → vm emits page_data_changed → ResourceList.set_data()
      → vm emits selection_changed → ResourceList.update_selection()
      → vm emits pagination_changed → ResourceList.update_pagination_bar()
      → vm creates bulk proxy, emits bulk_proxy_changed
        → Window calls EditorInterface.inspect_object()
```

### Resource Selection (Shift+Click)

```
User shift-clicks ResourceRow
  → ResourceList calls vm.select(resource, ctrl=false, shift=true)
    → vm computes range from _last_anchor
    → vm updates selected_paths, edited_resources
    → vm creates bulk proxy
    → vm emits selection_changed → ResourceList.update_selection()
    → vm emits bulk_proxy_changed → Window → EditorInterface.inspect_object()
```

### Filesystem Change (External Edit)

```
External file saved
  → EditorFileSystem.filesystem_changed
    → VREDataService._on_filesystem_changed()
      → debounce timer starts
      → (after 0.1s) data_service._rescan_resources_only()
        → mtime comparison
        → modifications only → data_service emits resources_modified(paths)
          → vm receives → emits rows_modified → ResourceList.refresh_row()
        → additions/deletions → data_service emits resources_changed
          → vm receives → full page rebuild
```

### Bulk Edit

```
User edits property in Inspector
  → EditorInspector.property_edited("damage")
    → Window checks: edited_object == vm.bulk_proxy? yes
    → Window calls vm.apply_bulk_edit("damage")
      → vm writes value to selected resources, saves each
      → vm emits rows_modified(changed_paths) → ResourceList refreshes
```
