# Visual Resources Editor — Plugin Implementation Guide

A Godot 4 `@tool` editor plugin for visually browsing, creating, bulk-editing, and deleting `.tres` resource files filtered by class type. Launched from the editor toolbar via **VisualResourcesEditor → Launch Visual Editor**.

---

## Architecture Overview

```
visual_resources_editor/
├── visual_resources_editor_plugin.gd   # EditorPlugin entry point (adds toolbar menu)
├── visual_resources_editor_toolbar.gd  # Toolbar menu: instantiates the editor window
├── core/
│   ├── data_models/
│   │   ├── resource_property.gd        # Typed data model for a single property definition
│   │   └── class_definition.gd         # Typed data model for a class (name, path, properties)
│   ├── project_class_scanner.gd        # Static utility: scans project classes, properties, .tres files
│   ├── state_manager.gd                # VREStateManager: central state (resources, properties, selection, pagination)
│   ├── state_manager.tscn              # Scene for VREStateManager + DebounceTimer child
│   └── bulk_editor.gd                  # BulkEditor: proxy-based multi-resource editing via Godot inspector
├── ui/
│   ├── visual_resources_editor_window.gd/.tscn  # Main Window: wires components, owns pagination bar + status label
│   ├── class_selector/
│   │   └── class_selector.gd/.tscn     # Dropdown + include-subclasses checkbox
│   ├── toolbar/
│   │   └── toolbar.gd/.tscn            # VREToolbar: New/Delete Selected/Refresh + owns SaveResourceDialog & ConfirmDeleteDialog
│   ├── resource_list/
│   │   ├── resource_list.gd/.tscn      # Table container: header + scrollable rows, supports incremental add/remove/modify
│   │   ├── header_row.gd/.tscn         # Column header labels
│   │   ├── resource_row.gd/.tscn       # One row per resource (Button with toggle_mode, self-contained delete)
│   │   ├── resource_field_label.gd/.tscn  # Label for a single property cell (owns display/format logic)
│   │   ├── header_field_label.tscn      # Label for a single header cell
│   │   └── field_separator.tscn         # VSeparator between columns
│   └── dialogs/
│       ├── save_resource_dialog.gd      # EditorFileDialog for creating new resources
│       ├── confirm_delete_dialog.gd     # ConfirmationDialog for deleting resources (moves to OS trash)
│       └── error_dialog.gd             # AcceptDialog for error messages
└── plugin.cfg
```

## Data Flow

1. **Class scanning**: `ProjectClassScanner` reads `ProjectSettings.get_global_class_list()` to discover all project classes that descend from `Resource`. Results are cached in `VREStateManager` as maps (`global_class_map`, `global_class_to_path_map`, `global_class_to_parent_map`) and the filtered list `global_class_name_list`.

2. **Resource scanning**: When a class is selected via `set_current_class()`, `VREStateManager` uses `set_current_class_resources(reseting: true)` to load all `.tres` files matching the class (and optionally its subclasses) via `ProjectClassScanner.load_classed_resources_from_dir()`. On filesystem changes, `set_current_class_resources(reseting: false)` performs an incremental scan via `_scan_class_resources_for_changes()` using mtime comparison. The scanner reads the first line of each `.tres` file via `FileAccess` to extract `script_class=` — it does NOT load the full resource for classification.

3. **State → UI (granular signals)**: `VREStateManager` emits different signals depending on the type of change:
   - `resources_replaced(resources, property_list)` — full page rebuild (class change, refresh, property change). Carries the current page slice + shared property list. `ResourceList.replace_resources()` rebuilds all rows.
   - `resources_added(resources)` — incremental, new .tres files detected on the current page. `ResourceList.add_resources()` appends rows without rebuilding.
   - `resources_removed(resources)` — incremental, deleted .tres files detected on the current page. `ResourceList.remove_resources()` removes specific rows.
   - `resources_modified(resources)` — incremental, modified .tres files detected on the current page. `ResourceList.modify_resources()` updates row display in place.
   - `pagination_changed(page, page_count)` — always emitted alongside data changes to keep the pagination bar in sync.

4. **Two-tier resource state**: `VREStateManager` maintains two levels of resource state:
   - `current_class_resources` + `_current_class_resources_mtimes` — all resources matching the selected class (across all pages).
   - `_current_page_resources` + `current_page_resources_mtimes` — the slice for the current page. `_scan_page_resources_for_changes()` diffs the previous and current page slices to emit granular signals (`resources_added`, `resources_removed`, `resources_modified`).

5. **Selection**: `VREStateManager` owns all selection state (`selected_resources`, `_selected_paths`, `_selected_resources_last_index`). `set_selected_resources()` dispatches to three handlers: `handle_select_shift()` (range select), `handle_select_ctrl()` (toggle), `handle_select_no_key()` (single select). Emits `selection_changed`. The window forwards selection to `ResourceList` (visual row highlighting), `VREToolbar` (delete-selected button label), and `BulkEditor`.

6. **Bulk editing**: `BulkEditor` creates a proxy resource matching the selected resources' script. For single selection, proxy copies the resource's values. For multi-selection, proxy uses defaults. When the user edits the proxy in Godot's Inspector, `BulkEditor` propagates the change to all selected resources and saves them.

7. **Filesystem reactivity**: Two `EditorFileSystem` signals drive updates:
   - `script_classes_updated` → debounced → `_handle_global_classes_updated()`: rebuilds class maps, detects class add/remove/rename, re-scans properties.
   - `filesystem_changed` → debounced → `_refresh_current_class_resources()`: calls `set_current_class_resources(false)` for incremental class resource scan, then `_set_current_page()` to diff the current page and emit granular signals.
   Both are debounced through a shared `DebounceTimer` (0.1s).

8. **Delete flow**:
   - **Single row delete**: Each `ResourceRow` owns a `ConfirmDeleteDialog` child. `DeleteBtn.pressed` → shows dialog → `confirmed` → moves file to OS trash. Fully self-contained, no signal bubbling.
   - **Bulk delete**: `VREToolbar` owns a `ConfirmDeleteDialog`. "Delete Selected" button passes selected resource paths to the dialog. Window keeps toolbar's selection in sync via `update_selection()`.

## Design Decisions

### Scene Unique Nodes (`%NodeName`)
All child node references use `%UniqueNode` directly in code — this is the project convention. Nodes are marked with `unique_name_in_owner = true` in their `.tscn`. This is intentional and preferred over `@onready var` or `@export` node references.

### Signal Connections: Scene vs Code
Signals are connected via scene (`[connection]` in `.tscn`) when both source and target are in the same scene. Code connections (`.connect()`) are used only for: dynamically created nodes, cross-scene callable forwarding, or direct signal re-emission.

### No UI Virtualization / Object Pooling
Pagination (50 items per page) keeps the row count bounded. Full row rebuild on page change via `resources_replaced` is acceptable at this scale. Incremental updates (`resources_added`/`removed`/`modified`) avoid full rebuilds for filesystem changes within the same page. Virtualization/pooling would add complexity without meaningful benefit.

### Incremental Resource Rescan (Two-Tier)
`EditorFileSystem` does not expose which specific files changed in `filesystem_changed`. The plugin maintains mtime dictionaries at two levels: `_current_class_resources_mtimes` (all resources for the class) and `current_page_resources_mtimes` (current page slice). `_scan_class_resources_for_changes()` diffs class-level mtimes, then `_scan_page_resources_for_changes()` diffs the page slice to determine exactly which rows need adding, removing, or updating — emitting granular signals instead of a full rebuild.

### Dialogs as Script-Only Nodes
Dialogs (`SaveResourceDialog`, `ConfirmDeleteDialog`, `ErrorDialog`) have no children and are fully configured at runtime. Per project convention, they are script-only nodes (`.gd` extending the dialog base type) added as children in their parent `.tscn` (toolbar, resource row) or programmatically for editor-only types (`ErrorDialog` in window's `create_and_add_dialogs()`).

### Delete Moves to OS Trash
Both `ConfirmDeleteDialog` (bulk) and `ResourceRow` (single) use `OS.move_to_trash()` instead of `DirAccess.remove_absolute()`. Files are recoverable from the OS trash/recycle bin. No undo/redo for deletion — version control is the secondary safety net (see CLAUDE.md).

### Two-Step Window Initialization
`create_and_add_dialogs()` and `connect_components()` are called separately after instantiation (not in `_ready()`). This is required because Window-inside-Window in `@tool` mode causes errors when Godot reloads with the scene open. The editor plugin toolbar controls this initialization sequence.

### ClassSelector Owns Include-Subclasses
The "Include subclasses" checkbox and its warning label live inside the `ClassSelector` scene. `ClassSelector` emits `include_subclasses_toggled(pressed)` and manages the warning label visibility internally. The window connects this signal to `VREStateManager.set_include_subclasses`.

### VREToolbar as Separate Scene
The toolbar (New / Delete Selected / Refresh) is its own scene (`ui/toolbar/toolbar.tscn`), separate from `ResourceList`. It owns `SaveResourceDialog` and `ConfirmDeleteDialog` for create and bulk-delete operations. The window passes class info and selection state to the toolbar.

## Data Models

### `ResourceProperty` (`core/data_models/resource_property.gd`)
Typed data class replacing raw `Dictionary` for property definitions. Used throughout the pipeline for columns, property lists, and signal payloads.

Properties: `name: String`, `type: int` (Variant.Type), `hint: int` (PropertyHint), `hint_string: String`.

### `ClassDefinition` (`core/data_models/class_definition.gd`)
Typed data class wrapping a project Resource class. Replaces passing raw class name strings + separate script paths + separate property arrays through the system.

Properties: `class_name_str: String`, `script_path: String`, `properties: Array[ResourceProperty]`.

### Signal Signatures

**VREStateManager:**
- `resources_replaced(resources: Array[Resource], current_shared_propery_list: Array[ResourceProperty])` — full page rebuild
- `resources_added(resources: Array[Resource])` — incremental: new resources on current page
- `resources_removed(resources: Array[Resource])` — incremental: deleted resources from current page
- `resources_modified(resources: Array[Resource])` — incremental: modified resources on current page
- `project_classes_changed(classes: Array[String])`
- `selection_changed(resources: Array[Resource])`
- `pagination_changed(page: int, page_count: int)`
- `current_class_renamed(new_name: String)`

**UI components:**
- `class_selected(class_name_str: String)`
- `include_subclasses_toggled(pressed: bool)`
- `refresh_requested`
- `error_occurred(message: String)`
- `row_clicked(resource: Resource, ctrl_held: bool, shift_held: bool)`
- `resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool)`

## Key Conventions
- All hardcoded `load()`/`preload()` use UIDs (`uid://...`), not string paths
- No `range()` in `for` loops — use `for i: int in count:` directly
- No `:=` type inference — always explicit types with `=`
- Constants are uppercase with explicit types
- `EditorFileSystemDirectory` references are never cached (freed on rescan)
- Signal connections via scene when possible; code connections only when necessary (see CLAUDE.md)
