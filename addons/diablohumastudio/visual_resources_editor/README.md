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
│   ├── state_manager.gd                # VREStateManager: central state (resources, columns, selection, pagination)
│   ├── state_manager.tscn              # Scene for VREStateManager + DebounceTimer child
│   └── bulk_editor.gd                  # BulkEditor: proxy-based multi-resource editing via Godot inspector
├── ui/
│   ├── visual_resources_editor_window.gd/.tscn  # Main Window: wires components together
│   ├── class_selector/
│   │   └── class_selector.gd/.tscn     # Dropdown to pick a Resource class
│   ├── resource_list/
│   │   ├── resource_list.gd/.tscn      # Table container: toolbar, header, scrollable rows, pagination
│   │   ├── header_row.gd/.tscn         # Column header labels
│   │   ├── resource_row.gd/.tscn       # One row per resource (Button with toggle_mode)
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

1. **Class scanning**: `ProjectClassScanner` reads `ProjectSettings.get_global_class_list()` to discover all project classes that descend from `Resource`. Results are cached in `VREStateManager` as maps (`global_classes_map`, `class_to_path_map`, `_classes_parent_map`).

2. **Resource scanning**: When a class is selected, `VREStateManager` uses `ProjectClassScanner.scan_folder_for_classed_tres_paths()` to find all `.tres` files matching the class (and optionally its subclasses). The scanner reads the first line of each `.tres` file via `FileAccess` to extract `script_class=` — it does NOT load the full resource for classification.

3. **State → UI**: `VREStateManager` emits `data_changed(resources, columns)` with only the current page slice. `ResourceList` rebuilds rows from this slice. Pagination is handled entirely in `VREStateManager` (PAGE_SIZE = 50).

4. **Selection**: `VREStateManager` owns all selection state (`selected_resources`, `_selected_paths`, `_last_anchor`). Supports click, Ctrl/Cmd+click (toggle), and Shift+click (range select across pages). Emits `selection_changed`.

5. **Bulk editing**: `BulkEditor` creates a proxy resource matching the selected resources' script. For single selection, proxy copies the resource's values. For multi-selection, proxy uses defaults. When the user edits the proxy in Godot's Inspector, `BulkEditor` propagates the change to all selected resources and saves them.

6. **Filesystem reactivity**: Two `EditorFileSystem` signals drive updates:
   - `script_classes_updated` → rebuild class maps, detect class add/remove/rename, re-scan properties
   - `filesystem_changed` → incremental mtime-based resource rescan (new/modified/deleted detection without full reload)
   Both are debounced through a shared `DebounceTimer` (0.1s).

## Design Decisions

### Scene Unique Nodes (`%NodeName`)
All child node references use `%UniqueNode` directly in code — this is the project convention. Nodes are marked with `unique_name_in_owner = true` in their `.tscn`. This is intentional and preferred over `@onready var` or `@export` node references.

### No UI Virtualization / Object Pooling
Pagination (50 items per page) keeps the row count bounded. Full row rebuild on page change is acceptable at this scale. Virtualization/pooling would add complexity without meaningful benefit.

### Incremental Resource Rescan (`_rescan_resources_only`)
`EditorFileSystem` does not expose which specific files changed in `filesystem_changed`. The plugin maintains `_known_resource_mtimes` and compares against current disk state. `scan_folder_for_classed_tres_paths()` re-reads the first line of each `.tres` file to check the class — this is the best available approach given Godot's EditorFileSystem API limitations.

### Dialogs as Script-Only Nodes
Dialogs (`SaveResourceDialog`, `ConfirmDeleteDialog`, `ErrorDialog`) have no children and are fully configured at runtime. Per project convention, they are script-only nodes (`.gd` extending the dialog base type) added to the window programmatically in `create_and_add_dialogs()`.

### Delete Moves to OS Trash
`ConfirmDeleteDialog` uses `OS.move_to_trash()` instead of `DirAccess.remove_absolute()`. Files are recoverable from the OS trash/recycle bin. No undo/redo for deletion — version control is the secondary safety net (see CLAUDE.md).

### Two-Step Window Initialization
`create_and_add_dialogs()` and `connect_components()` are called separately after instantiation (not in `_ready()`). This is required because Window-inside-Window in `@tool` mode causes errors when Godot reloads with the scene open. The toolbar controls this initialization sequence.

## Data Models

### `ResourceProperty` (`core/data_models/resource_property.gd`)
Typed data class replacing raw `Dictionary` for property definitions. Used throughout the pipeline for columns, property lists, and signal payloads.

Properties: `name: String`, `type: int` (Variant.Type), `hint: int` (PropertyHint), `hint_string: String`.

### `ClassDefinition` (`core/data_models/class_definition.gd`)
Typed data class wrapping a project Resource class. Replaces passing raw class name strings + separate script paths + separate property arrays through the system.

Properties: `class_name_str: String`, `script_path: String`, `properties: Array[ResourceProperty]`.

### Signal Signatures
- `data_changed(resources: Array[Resource], columns: Array[ResourceProperty])`
- `project_classes_changed(classes: Array[String])`
- `selection_changed(resources: Array[Resource])`
- `pagination_changed(page: int, page_count: int)`

## Key Conventions
- All hardcoded `load()`/`preload()` use UIDs (`uid://...`), not string paths
- No `range()` in `for` loops — use `for i: int in count:` directly
- No `:=` type inference — always explicit types with `=`
- Constants are uppercase with explicit types
- `EditorFileSystemDirectory` references are never cached (freed on rescan)
