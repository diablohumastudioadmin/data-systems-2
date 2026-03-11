# Visual Resources Editor Plugin — Implementation Plan

## Context

Lightweight plugin to browse `.tres` resources of any user-defined class across the project as a table, with CRUD and bulk editing. Does NOT manage schemas or file locations. Window-based (F3 hotkey).

## Existing Boilerplate

```
addons/diablohumastudio/visual_resources_editor/
├── plugin.cfg
├── visual_resources_editor_plugin.gd        # Toolbar menu registration
├── visual_resources_editor_toolbar.gd       # "Launch Visual Editor" (F3), opens window
└── ui/
    ├── visual_resources_editor_window.tscn  # Window shell
    └── visual_resources_editor_window.gd    # close_requested handler
```

## Architecture — Modular Scenes

The window composes two independent scenes. Each row in the list is its own scene instance.

```
Window
├── ClassSelector (scene)        ← picks which Resource class to browse
└── ResourceList (scene)         ← shows all instances + toolbar + CRUD
    └── ScrollContainer
        └── VBox
            ├── ResourceRow (scene instance per .tres)
            ├── ResourceRow ...
            └── ...
```

## Files to Create

```
addons/diablohumastudio/visual_resources_editor/ui/
├── class_selector/
│   ├── class_selector.tscn          # Searchable class picker
│   └── class_selector.gd
├── resource_list/
│   ├── resource_list.tscn           # List of rows + toolbar (create/delete/bulk/save)
│   ├── resource_list.gd
│   ├── resource_row.tscn            # One row per resource instance
│   └── resource_row.gd
└── bulk_edit_proxy.gd               # Dynamic single-field Inspector proxy
```

## Files to Modify

- `ui/visual_resources_editor_window.tscn` — compose ClassSelector + ResourceList
- `ui/visual_resources_editor_window.gd` — wire signals between children, filesystem debounce

---

## Step 1: `bulk_edit_proxy.gd`

Same pattern as database_manager's. No `class_name`. ~54 lines:
- `setup(field_name, variant_type, initial_value, hint, hint_string)`
- `_get_property_list()` → one dynamic field
- `_set()` → emits `value_changed(field_name, new_value)`

---

## Step 2: `class_selector.tscn` + `.gd`

**Scene:**
```
ClassSelector (HBoxContainer)
  Label "Class:"
  %SearchField (LineEdit) [placeholder "Type to search...", h_size_flags EXPAND_FILL]
  %ClassList (PopupMenu)
```

**Signal:** `class_selected(class_name: String, script_path: String)`

**Logic:**
- On `_ready()`, gather user classes: `ProjectSettings.get_global_class_list()` → filter to Resource descendants. Cache full list.
- `SearchField.text_changed` → filter cached list, populate `%ClassList` popup, show it below the field
- `ClassList.id_pressed` → emit `class_selected` with name + script path, update SearchField text
- Also support Enter key in SearchField to confirm top result

---

## Step 3: `resource_row.tscn` + `.gd`

A single row representing one `.tres` instance.

**Scene:**
```
ResourceRow (HBoxContainer) [h_size_flags EXPAND_FILL]
  %SelectCheck (CheckBox)                    # For multi-select / bulk edit
  %FileNameLabel (Label)                     # Filename (tooltip = full path)
  %FieldsContainer (HBoxContainer)           # Dynamic: one Label per property value
  %DeleteBtn (Button) [text "X", flat=true]  # Per-row delete
```

**Signals:**
- `row_clicked(resource_path: String)`
- `row_selected(resource_path: String, selected: bool)` — from checkbox toggle
- `delete_requested(resource_path: String)`

**Logic:**
- `setup(resource: Resource, columns: Array[Dictionary])`:
  - Store resource ref and path
  - Set `%FileNameLabel.text` = filename, tooltip = full path
  - For each column in `columns`: create a Label in `%FieldsContainer` with formatted value
  - Color fields: set label background color
- `%SelectCheck.toggled` → emit `row_selected`
- Click on row (via `gui_input`) → emit `row_clicked`
- `%DeleteBtn.pressed` → emit `delete_requested`
- `update_display()` — refresh labels from current resource values (after edit)
- Visual highlight when selected (StyleBoxFlat background)

---

## Step 4: `resource_list.tscn` + `.gd`

**Scene:**
```
ResourceList (VBoxContainer) [anchors full rect]
  Toolbar (HBoxContainer)
    %CreateBtn (Button)          [text "New"]
    %DeleteSelectedBtn (Button)  [text "Delete Selected"]
    VSeparator
    %BulkEditBtn (MenuButton)    [text "Bulk Edit", disabled=true]
    VSeparator
    %SaveAllBtn (Button)         [text "Save All"]
    %RefreshBtn (Button)         [text "Refresh"]
    VSeparator
    %IncludeSubclassesCheck (CheckBox) [text "Include subclasses", toggled_on=true]
  %HeaderRow (HBoxContainer)     # Column headers (dynamic labels)
  %ScrollContainer (ScrollContainer) [v_size_flags EXPAND_FILL]
    %RowsContainer (VBoxContainer)   # ResourceRow instances go here
  %StatusLabel (Label)
```

**Signals:**
- `resource_clicked(resource: Resource)` — for Inspector integration

**Public method:** `set_class(class_name: String, script_path: String)` — called by window when class selected

**Logic:**

### Scanning
- Recursively walk `res://` with `DirAccess`, skip `addons/` and hidden dirs
- For each `.tres`, read first ~300 bytes, parse `script_class="X"` or `type="X"`
- If "Include subclasses" on: build valid set from `ProjectSettings.get_global_class_list()` parent→children map
- Cache results

### Building rows
- Get property list: `load(script_path).new().get_property_list()` → filter to `PROPERTY_USAGE_EDITOR`, skip `resource_*`, `script`, `metadata/*`
- Build `%HeaderRow` labels matching columns
- For each scanned path: load resource, instantiate `resource_row.tscn`, call `setup(resource, columns)`, add to `%RowsContainer`

### Selection & Inspector
- `resource_row.row_clicked` → `EditorInterface.inspect_object(resource)`, highlight row
- `inspector.property_edited` → find affected row, call `update_display()`, mark dirty

### Bulk edit
- When any checkbox toggled, count selected rows → enable/disable `%BulkEditBtn`
- `%BulkEditBtn` popup lists property names
- On field selected → create BulkEditProxy, show in Inspector
- `proxy.value_changed` → apply to all checked resources, update rows, mark dirty

### Create
- Open `EditorFileDialog(SAVE, "*.tres")` → `load(script_path).new()` → `ResourceSaver.save()` → rescan

### Delete
- Per-row delete or "Delete Selected" for checked rows
- Confirmation dialog → `DirAccess.remove_absolute()` → rescan

### Save All
- `ResourceSaver.save(resource, path)` for each dirty resource → clear dirty set

---

## Step 5: Wire up the window

**`visual_resources_editor_window.tscn`** — add ClassSelector + ResourceList as children, set window size ~1200x700

**`visual_resources_editor_window.gd`**:
- Connect `ClassSelector.class_selected` → `ResourceList.set_class()`
- Connect `ResourceList.resource_clicked` → `EditorInterface.inspect_object()`
- Connect `EditorFileSystem.filesystem_changed` → debounce timer → `ResourceList.refresh()`
- Handle unsaved changes on window close

---

## Implementation Order

1. `bulk_edit_proxy.gd` — standalone
2. `resource_row.tscn` + `.gd` — standalone row scene
3. `class_selector.tscn` + `.gd` — standalone class picker
4. `resource_list.tscn` + `.gd` — main list (uses resource_row)
5. Wire up window `.tscn` + `.gd` (composes class_selector + resource_list)

## Verification

1. F3 → window opens with class selector + empty list
2. Type class name → filtered suggestions → select → list populates with .tres rows
3. Click row → Inspector shows resource
4. Check multiple rows → Bulk Edit → pick field → change propagates
5. "New" → save dialog → creates .tres → appears in list
6. "X" on row or "Delete Selected" → file removed → list updates
7. "Save All" → dirty resources saved

## TODO — Performance & Quality

- [ ] **Debounce `filesystem_changed`** — Add a Timer (e.g. 0.3s) to coalesce rapid `filesystem_changed` signals into a single `_rescan_and_rebuild()` call
- [ ] **Eager loading** — All matching `.tres` files are loaded into RAM at rebuild time. For large datasets, consider virtualized/lazy row loading (only load resources for visible rows)
- [ ] **O(n²) subclass propagation** in `_build_valid_class_set()` — Replace the `while changed` loop with a parent→children map + BFS/DFS for linear-time resolution
- [ ] **O(n²) inheritance check** in `class_selector.gd:_is_resource_descendant()` — Pre-index `get_global_class_list()` into a Dictionary before walking the inheritance chain

## Reference (copy patterns from, don't import)

- [data_instance_editor.gd](addons/diablohumastudio/database_manager/ui/data_instance_editor/data_instance_editor.gd) — Inspector integration, value display, selection handling
- [bulk_edit_proxy.gd](addons/diablohumastudio/database_manager/ui/data_instance_editor/bulk_edit_proxy.gd) — proxy pattern
