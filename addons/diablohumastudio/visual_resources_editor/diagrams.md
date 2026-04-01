# Visual Resources Editor - Architecture & Information Flow

The plugin uses a clean **MVVM-like pattern**. The `VisualResourcesEditorWindow` is a pure **dependency injector**: its only job in `_ready()` is to hand the `VREStateManager` reference to every child component. After that, components talk directly to `state_manager` — no coordinator in the middle.

---

## 1. Window Subdivision (Component Hierarchy)

```mermaid
graph TD
    classDef window fill:#2d3748,stroke:#4a5568,color:#fff
    classDef layout fill:#4a5568,stroke:#718096,color:#fff
    classDef view fill:#3182ce,stroke:#2b6cb0,color:#fff
    classDef logic fill:#38a169,stroke:#2f855a,color:#fff

    Window[VisualResourcesEditorWindow]:::window

    subgraph View / UI Layout
        Margin[MarginContainer]:::layout
        VBox[VBoxContainer]:::layout

        ClassSel[ %ClassSelector ]:::view
        SubFilt[ %SubclassFilter ]:::view
        Toolbar[ %Toolbar ]:::view
        ResList[ %ResourceList ]:::view
        PagBar[ %PaginationBar ]:::view
        Status[ %StatusLabel ]:::view
        Dialogs[ %Dialogs ]:::view

        subgraph Dialogs scene
            SaveDlg[ %SaveResourceDialog ]:::view
            DelDlg[ %ConfirmDeleteDialog ]:::view
            ErrDlg[ %ErrorDialog ]:::view
        end
    end

    subgraph Core / Logic
        State[ %VREStateManager ]:::logic
        Bulk[ %BulkEditor ]:::logic
    end

    Window --> Margin
    Margin --> VBox
    VBox --> ClassSel
    VBox --> SubFilt
    VBox --> Toolbar
    VBox --> ResList
    VBox --> PagBar
    VBox --> Status
    Window --> Dialogs
    Dialogs --> SaveDlg
    Dialogs --> DelDlg
    Dialogs --> ErrDlg
    Window --> State
    Window --> Bulk
```

**Component responsibilities:**
- **`%ClassSelector`**: dropdown to pick the resource class; follows class renames automatically.
- **`%SubclassFilter`**: toggle to include/exclude subclass instances.
- **`%Toolbar`**: Create, Delete Selected, Refresh buttons.
- **`%ResourceList`**: scrollable table of resource rows. Each `ResourceRow` calls state_manager directly on press.
- **`%PaginationBar`**: Prev/Next buttons wired directly to `state_manager.prev_page` / `next_page`.
- **`%StatusLabel`**: shows resource count or selection count.
- **`%Dialogs`**: owns `SaveResourceDialog`, `ConfirmDeleteDialog`, `ErrorDialog`. Each listens to a specific state_manager signal.
- **`%VREStateManager`**: all data, all signals, all filesystem tracking.
- **`%BulkEditor`**: listens to `selection_changed`, maintains the inspector proxy, applies edits to all selected resources.

---

## 2. High-Level Information Flow

Window is a pure DI injector. Every component holds a `state_manager` reference and calls it or listens to it directly. There are no intermediate signals relayed through the window.

```mermaid
flowchart LR
    classDef ui fill:#3182ce,stroke:#2b6cb0,color:#fff
    classDef state fill:#38a169,stroke:#2f855a,color:#fff
    classDef logic fill:#805ad5,stroke:#6b46c1,color:#fff

    subgraph UI Components
        ClassSel[ClassSelector]:::ui
        SubFilt[SubclassFilter]:::ui
        Toolbar[VREToolbar]:::ui
        ResList[ResourceList]:::ui
        Row[ResourceRow]:::ui
        PagBar[PaginationBar]:::ui
        StatusLbl[StatusLabel]:::ui
        Dialogs[Dialogs]:::ui
    end

    State[VREStateManager]:::state
    Bulk[BulkEditor]:::logic

    %% calls to state
    ClassSel -- "set_current_class()" --> State
    SubFilt -- "set_include_subclasses()" --> State
    Toolbar -- "request_create / request_delete / refresh" --> State
    Row -- "set_selected_resources()" --> State
    PagBar -- "prev_page() / next_page()" --> State
    Bulk -- "notify_resources_edited() / report_error()" --> State

    %% signals from state
    State -- "project_classes_changed\ncurrent_class_renamed" --> ClassSel
    State -- "resources_replaced\nresources_added/removed/modified" --> ResList
    State -- "resources_edited" --> ResList
    State -- "selection_changed" --> StatusLbl
    State -- "selection_changed" --> Toolbar
    State -- "selection_changed" --> Bulk
    State -- "pagination_changed" --> PagBar
    State -- "resources_replaced\nresources_added\nresources_removed" --> StatusLbl
    State -- "create_new_resource_requested" --> Dialogs
    State -- "delete_selected_requested" --> Dialogs
    State -- "error_occurred" --> Dialogs
```

---

## 3. Data Flow: Selecting a Class

```mermaid
sequenceDiagram
    participant User
    participant ClassSel as UI: ClassSelector
    participant State as VREStateManager
    participant Scanner as ProjectClassScanner
    participant ResList as UI: ResourceList
    participant PagBar as UI: PaginationBar

    User->>ClassSel: Selects class "AllyData"
    ClassSel->>State: set_current_class("AllyData")

    activate State
    State->>Scanner: get_descendant_classes() — resolve included classes
    State->>Scanner: get_properties_from_script_names() — shared property list
    State->>Scanner: load_classed_resources_from_dir() — load .tres files
    Scanner-->>State: Array[Resource]
    State->>State: reset to page 0
    State-->>ResList: resources_replaced(page_resources, property_list)
    State-->>PagBar: pagination_changed(0, page_count)
    deactivate State

    ResList->>ResList: _clear_rows()
    ResList->>ResList: _add_row() × N
```

---

## 4. Data Flow: Selection & Bulk Editing

```mermaid
sequenceDiagram
    participant User
    participant Row as UI: ResourceRow
    participant State as VREStateManager
    participant Bulk as BulkEditor
    participant Inspector as Godot EditorInspector
    participant ResList as UI: ResourceList
    participant Toolbar as UI: VREToolbar

    User->>Row: Clicks row (no modifier)
    Row->>State: set_selected_resources(resource, false, false)

    activate State
    State->>State: handle_select_no_key() — clears list, appends resource
    State-->>Row: selection_changed([resource]) → row highlights
    State-->>Toolbar: selection_changed → updates "Delete Selected (1)"
    State-->>Bulk: selection_changed([resource])
    deactivate State

    activate Bulk
    Bulk->>Bulk: _create_bulk_proxy() — creates script instance, copies values
    Bulk->>Inspector: EditorInterface.inspect_object(_bulk_proxy)
    deactivate Bulk

    Note over User, Inspector: User edits a property in Godot's Inspector panel

    User->>Inspector: Changes 'damage' to 50
    Inspector->>Bulk: property_edited("damage")

    activate Bulk
    Bulk->>Bulk: reads new value from _bulk_proxy
    loop For each selected resource
        Bulk->>Bulk: res.set("damage", 50)
        Bulk->>Bulk: ResourceSaver.save(res)
    end
    Bulk->>State: notify_resources_edited(saved)
    deactivate Bulk

    State-->>ResList: resources_edited([resource])
    ResList->>ResList: _refresh_row() — updates label values in place
```

---

## 5. Data Flow: Filesystem Events (Background Loop)

Two separate paths depending on what changed on disk:

**A — File added/removed/modified (no class change):**
`EditorFileSystem.filesystem_changed` → `VREStateManager._on_filesystem_changed()` → debounce (`RescanDebounceTimer`) → `_refresh_current_class_resources()` → `_scan_class_resources_for_changes()` (mtime comparison) → granular `resources_added / resources_removed / resources_modified` emitted → `pagination_changed`.

Selection is restored: `_restore_selection()` re-matches previous paths in the new resource list.

**B — Script class changed (added/removed/renamed class or property schema):**
`EditorFileSystem.script_classes_updated` → `_on_script_classes_updated()` → debounce → `_handle_global_classes_updated()`:
- If class list unchanged: checks for property schema changes → if changed, resaves all resources of that class, emits `resources_replaced`.
- If class list changed: emits `project_classes_changed` → ClassSelector updates dropdown.
  - If current class was renamed: emits `current_class_renamed` → ClassSelector follows it.
  - If current class was deleted: clears view.
  - If subclass set changed: calls `refresh_resource_list_values()`.
- Orphaned resources (from a deleted class) are resaved to strip the missing script reference.

Note: when a `.gd` script changes, both signals fire in the same scan cycle. The `_classes_update_pending` flag on path B suppresses path A until B finishes.

---

## Event Catalog

### A. User Actions

| # | Action | Where |
|---|--------|--------|
| 1 | Open the plugin (F3 / menu) | VisualResourcesEditorToolbar menu |
| 2 | Close the plugin (Escape / ✕) | Window title bar or keyboard |
| 3 | Select a class | ClassSelector dropdown |
| 4 | Toggle "Include Subclasses" | SubclassFilter checkbox |
| 5 | Click a resource row — single select | ResourceRow button |
| 6 | Ctrl+click a resource row — toggle | ResourceRow button |
| 7 | Shift+click a resource row — range select | ResourceRow button |
| 8 | Click "Create New" | VREToolbar |
| 9 | Click "Delete Selected" | VREToolbar |
| 10 | Click a row's own Delete button | ResourceRow |
| 11 | Click "Refresh" | VREToolbar |
| 12 | Click Next page / Prev page | PaginationBar |
| 13 | Edit a property in Godot Inspector (bulk edit) | Godot EditorInspector |
| 14a | Create a `.tres` of the viewed class externally | File system |
| 14b | Create a `.tres` of a different class externally | File system |
| 15a | Delete a `.tres` of the viewed class externally | File system |
| 15b | Delete a `.tres` of a different class externally | File system |
| 16a | Modify a `.tres` of the viewed class externally | File system |
| 16b | Modify a `.tres` of a different class externally | File system |
| 17 | Create a new `.gd` script with `class_name` extending Resource | File system |
| 18 | Delete a `.gd` script (remove class) | File system |
| 19 | Rename a class (`class_name` line changes) | File system |
| 20 | Add/remove/change `@export` properties in a `.gd` script | File system |

### B. Editor-Triggered Events (automatic Godot behavior)

| # | Event | Notes |
|---|-------|-------|
| 1 | `EditorFileSystem.filesystem_changed` | Fires after Godot's internal scan detects any file add/remove/modify |
| 2 | `EditorFileSystem.script_classes_updated` | Fires when the global class map changes |
| 3 | Both fire sequentially on `.gd` change | `script_classes_updated` first, then `filesystem_changed` in the same scan cycle |
| 4 | `EditorInspector.property_edited(property)` | Fires when user changes any Inspector value; BulkEditor listens |
| 5 | `EditorFileSystemDirectory` refresh | Godot frees and recreates the directory tree on every scan — never cache these references |

### C. Desired Outcomes

| # | Observable result |
|---|-------------------|
| 1 | Class names populate ClassSelector dropdown on plugin open |
| 2 | New class appears in ClassSelector dropdown |
| 3 | Class disappears from ClassSelector dropdown |
| 4 | ClassSelector follows a renamed class (selection updates to new name) |
| 5 | New row appears in ResourceList |
| 6 | Row disappears from ResourceList |
| 7 | Row values update in ResourceList |
| 8 | Columns update in ResourceList header and rows (schema change) |
| 9 | Selection highlights update in ResourceList |
| 10 | Selection is preserved after list refresh (same paths re-selected) |
| 11 | PaginationBar shows/hides based on page count |
| 12 | PaginationBar prev/next disabled correctly at boundaries |
| 13 | StatusLabel shows visible resource count |
| 14 | StatusLabel shows selection count while something is selected |
| 15 | Inspector shows bulk proxy when resources are selected |
| 16 | Inspector clears when selection is empty or cross-class |
| 17 | Error dialog appears on save/delete failures |
| 18 | View clears when current class is deleted and not renamed |

---

### D. User Action → Call Chain → state_manager

| User Action | Component | Handler | Intermediate steps | state_manager method |
|-------------|-----------|---------|-------------------|---------------------|
| Open plugin (F3 / menu) | VisualResourcesEditorToolbar | `_on_menu_id_pressed(0)` | `open_visual_editor_window()` → instantiate window → `_ready()` sets all `.state_manager` properties | — (no direct call; setup only) |
| Close plugin (Esc / ✕) | VisualResourcesEditorWindow | `_unhandled_input()` | `close_requested.emit()` → `_on_close_requested()` → `queue_free()` | — |
| Select a class | ClassSelector | `_on_class_dropdown_item_selected(idx)` | — | `set_current_class(name)` |
| Toggle Include Subclasses | SubclassFilter | `_on_include_subclasses_check_toggled(pressed)` | — | `set_include_subclasses(pressed)` |
| Click row (no modifier) | ResourceRow | `_on_pressed()` | reads `Input.is_key_pressed()` | `set_selected_resources(res, false, false)` |
| Ctrl+click row | ResourceRow | `_on_pressed()` | reads `Input.is_key_pressed(KEY_CTRL/META)` | `set_selected_resources(res, true, false)` |
| Shift+click row | ResourceRow | `_on_pressed()` | reads `Input.is_key_pressed(KEY_SHIFT)` | `set_selected_resources(res, false, true)` |
| Click "Create New" | VREToolbar | `_on_create_btn_pressed()` | — | `request_create_new_resouce()` → emits `create_new_resource_requested` → SaveResourceDialog shows → after user picks path: `ResourceSaver.save()` → filesystem event |
| Click "Delete Selected" | VREToolbar | `_on_delete_selected_pressed()` | reads `state_manager._selected_paths` | `request_delete_selected_resources(paths)` → emits `delete_selected_requested` → ConfirmDeleteDialog shows → after confirm: `OS.move_to_trash()` + `efs.update_file()` → filesystem event |
| Click row's Delete button | ResourceRow | `_on_delete_pressed()` | — | `request_delete_selected_resources([resource.resource_path])` → same dialog flow as above |
| Click "Refresh" | VREToolbar | `_on_refresh_btn_pressed()` | — | `refresh_resource_list_values()` |
| Click Next page | PaginationBar | `%NextBtn.pressed` connected | — | `next_page()` |
| Click Prev page | PaginationBar | `%PrevBtn.pressed` connected | — | `prev_page()` |
| Edit property in Inspector | Godot EditorInspector | `property_edited` signal | BulkEditor `_on_inspector_property_edited()` → `res.set()` + `ResourceSaver.save()` per resource | `notify_resources_edited(saved)` and/or `report_error(msg)` |

---

### E. state_manager Method → Desired Outcomes

| state_manager method | What it does internally | Signals emitted | Outcomes |
|----------------------|------------------------|----------------|---------|
| `set_current_class(name)` | Calls `refresh_resource_list_values()` | `resources_replaced`, `pagination_changed` | ResourceList rebuilds all rows; PaginationBar resets to page 0; StatusLabel updates count |
| `set_include_subclasses(value)` | Calls `refresh_resource_list_values()` | `resources_replaced`, `pagination_changed` | Same as above |
| `refresh_resource_list_values()` | Resolves classes, scans properties, loads resources, resets page, restores selection | `resources_replaced`, `pagination_changed`, `selection_changed` | Full list rebuild; columns update; selection preserved |
| `set_selected_resources(res, ctrl, shift)` | Shift=range, Ctrl=toggle, none=single; updates `selected_resources` | `selection_changed` | Row highlights update; toolbar count updates; BulkEditor creates/clears inspector proxy |
| `request_create_new_resouce()` | Emits signal only; dialog + filesystem do the rest | `create_new_resource_requested` | SaveResourceDialog opens |
| `request_delete_selected_resources(paths)` | Emits signal only; dialog + filesystem do the rest | `delete_selected_requested` | ConfirmDeleteDialog opens |
| `next_page()` / `prev_page()` | Clamps page, slices new page window, diffs against previous | `resources_added`, `resources_removed`, `resources_modified`, `pagination_changed` | ResourceList adds/removes/updates rows for the new page; PaginationBar updates |
| `notify_resources_edited(resources)` | Emits signal only | `resources_edited` | ResourceList refreshes display values in affected rows (no rebuild) |
| `report_error(message)` | Emits signal only | `error_occurred` | ErrorDialog shows the message |
| `_on_filesystem_changed()` (auto) | Debounces → `_scan_class_resources_for_changes()` → mtime diff → restores selection | `resources_added`, `resources_removed`, `resources_modified`, `pagination_changed`, `selection_changed` | New/deleted/modified rows update in place; selection restored by path |
| `_handle_global_classes_updated()` (auto) | Rebuilds class maps; detects renames, deletions, subclass-set changes, schema changes | `project_classes_changed`, `current_class_renamed`, `resources_replaced`, `pagination_changed` | Dropdown updates; class rename followed; view clears or refreshes |

---

## Diagrams: User Actions → state_manager → Outcomes

### User Actions → state_manager calls

```mermaid
flowchart TD
    classDef action fill:#2b4c7e,stroke:#4a7ebf,color:#fff
    classDef sm fill:#38a169,stroke:#2f855a,color:#fff

    A1([Select class]):::action --> SM1[set_current_class]:::sm
    A2([Toggle subclasses]):::action --> SM2[set_include_subclasses]:::sm
    A3([Click row]):::action --> SM3[set_selected_resources]:::sm
    A4([Ctrl+click row]):::action --> SM3
    A5([Shift+click row]):::action --> SM3
    A6([Click Refresh]):::action --> SM4[refresh_resource_list_values]:::sm
    A7([Click Create New]):::action --> SM5[request_create_new_resouce]:::sm
    A8([Click Delete Selected]):::action --> SM6[request_delete_selected_resources]:::sm
    A9([Click row Delete btn]):::action --> SM6
    A10([Click Next page]):::action --> SM7[next_page]:::sm
    A11([Click Prev page]):::action --> SM8[prev_page]:::sm
    A12([Edit in Inspector]):::action --> SM9[notify_resources_edited]:::sm
    A12 -.->|on error| SM10[report_error]:::sm

    SM1 --> SM4
    SM2 --> SM4
```

### state_manager signals → UI outcomes

```mermaid
flowchart LR
    classDef sm fill:#38a169,stroke:#2f855a,color:#fff
    classDef sig fill:#744210,stroke:#b7791f,color:#fff
    classDef out fill:#2d3748,stroke:#718096,color:#fff

    SM_replace[resources_replaced]:::sig
    SM_add[resources_added]:::sig
    SM_rem[resources_removed]:::sig
    SM_mod[resources_modified]:::sig
    SM_edit[resources_edited]:::sig
    SM_sel[selection_changed]:::sig
    SM_pag[pagination_changed]:::sig
    SM_cls[project_classes_changed]:::sig
    SM_ren[current_class_renamed]:::sig
    SM_create[create_new_resource_requested]:::sig
    SM_del[delete_selected_requested]:::sig
    SM_err[error_occurred]:::sig

    SM_replace --> O1[ResourceList rebuilds all rows]:::out
    SM_replace --> O2[StatusLabel shows count]:::out
    SM_add --> O3[ResourceList adds rows]:::out
    SM_rem --> O4[ResourceList removes rows]:::out
    SM_mod --> O5[ResourceList updates row values]:::out
    SM_edit --> O5
    SM_sel --> O6[ResourceList updates highlights]:::out
    SM_sel --> O7[Toolbar updates Delete count]:::out
    SM_sel --> O8[BulkEditor creates/clears proxy]:::out
    SM_sel --> O9[StatusLabel shows selection count]:::out
    SM_pag --> O10[PaginationBar updates page label & buttons]:::out
    SM_cls --> O11[ClassSelector rebuilds dropdown]:::out
    SM_ren --> O12[ClassSelector follows renamed class]:::out
    SM_create --> O13[SaveResourceDialog opens]:::out
    SM_del --> O14[ConfirmDeleteDialog opens]:::out
    SM_err --> O15[ErrorDialog shows message]:::out
```
