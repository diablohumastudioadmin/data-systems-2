# Visual Resources Editor — Codex Analysis (Harsh)

Scope: `addons/diablohumastudio/visual_resources_editor`.

This review is intentionally blunt and risk-focused. I’m calling out bugs, architectural debt, and UX/maintenance pitfalls first, then documenting function-by-function behavior and how objects communicate.

**Key Findings (Harsh Summary)**
1. **No Undo/Redo for destructive operations.** Bulk edits and deletes bypass `UndoRedo`, so mistakes are irreversible. This is a major editor UX regression and violates typical Godot editor expectations. See `core/bulk_editor.gd` and `ui/dialogs/confirm_delete_dialog.gd`.
1. **Resource class detection is brittle.** `ProjectClassScanner.get_class_from_tres_file` only reads the first line of the `.tres` file and assumes `script_class` is there. That can easily break for real-world files or formatting changes. This is a functional correctness risk.
1. **State manager performs heavy full scans synchronously on class selection.** `VREStateManager.refresh_resource_list_values` does full property scan + full resource scan on every change. This will scale poorly with project size. There is no async scan or progress feedback. UI will hitch.
1. **Inconsistent and fragile state updates.** `VREStateManager._rescan_resources_only` only updates `resources` and selection, but does not re-emit updated columns when scripts change unless `script_classes_updated` fires. Filesystem changes can yield a stale column set.
1. **Potentially invalid property check in bulk edit.** `if property not in res` is dubious for `Resource`. If it doesn’t behave as expected, bulk edits silently skip fields. If it does behave, it’s still unclear and non-idiomatic.
1. **No error handling for resource load failures in scans.** A failing load simply skips the resource; the UI silently hides it. This will look like data loss.
1. **Naming mistakes and inconsistent class names.** `ComfirmDeleteDialog` (typo) is used across code and is a sign of weak API hygiene.
1. **Global editor inspector is hijacked by BulkEditor.** The bulk proxy takes over the editor inspector without an obvious way to restore the previous inspected object. This can be disruptive when the window is open and user expects inspector state to persist.

**System Architecture (How Pieces Talk)**
1. **Entry point**
1. `visual_resources_editor_plugin.gd` registers a toolbar submenu via `MainToolbarPlugin`.
1. `visual_resources_editor_toolbar.gd` builds the menu and spawns the editor window on demand.
1. The editor window scene `ui/visual_resources_editor_window.tscn` is instantiated and inserted into the editor UI.

2. **Core data flow**
1. `VisualResourcesEditorWindow` wires UI to `VREStateManager` and `BulkEditor`.
1. Class selection -> `VREStateManager.set_class()` -> full scan -> `data_changed` signal -> `ResourceList.set_data()`.
1. Row selection -> `ResourceList.row_clicked` -> `VREStateManager.select()` -> `selection_changed` -> `BulkEditor.edited_resources`.
1. Bulk edits happen in Godot Inspector -> `BulkEditor._on_inspector_property_edited` -> save each resource -> `resources_edited` -> `ResourceList.refresh_row()`.
1. Delete requested -> `ConfirmDeleteDialog` removes files -> filesystem update -> `VREStateManager` rescan.

3. **Dependencies and coupling**
1. `VREStateManager` owns scanning, selection, pagination, and data normalization. It’s doing too much.
1. UI nodes depend on concrete node paths (`%VREStateManager`, `%ResourceList`, etc.), not interfaces.
1. `BulkEditor` is tightly coupled to editor inspector and relies on external state injected by the window.

**Component Review (By Class + Functions)**

## `visual_resources_editor_plugin.gd`
**Class**: implicit plugin class (extends `DiabloHumaStudioPlugin`).

1. `func _enter_tree()`
1. Calls `add_toolbar_menu()` immediately. OK.

1. `func add_toolbar_menu()`
1. Instantiates `VisualResourcesEditorToolbar` and registers it under `MainToolbarPlugin`.
1. Hard-coded submenu name. No duplicate protection if multiple instances are loaded.

1. `func _exit_tree()`
1. Removes toolbar submenu. Good.

**Harsh notes**
1. No handling for plugin reload while toolbar exists. It relies entirely on `MainToolbarPlugin` cleanup. If the menu is left alive, it could leak.

## `visual_resources_editor_toolbar.gd`
**Class**: `VisualResourcesEditorToolbar`.

1. `func _enter_tree()`
1. Adds a single menu item with F3 shortcut. No config, no rebind, no editor shortcut integration.

1. `func _exit_tree()`
1. Frees the window if it exists. Good hygiene.

1. `func _on_menu_id_pressed(id)`
1. `match` on `id` only handles `0`. Anything else silently ignored.

1. `func open_visual_editor_window()`
1. Focuses existing window if it exists.
1. Instantiates window from `PackedScene`, adds to editor base control.
1. Calls `create_and_add_dialogs()` and `connect_components()` manually.
1. Hooks `close_requested` to null out the reference.

**Harsh notes**
1. `create_and_add_dialogs` and `connect_components` are manual lifecycles instead of `_ready()`. This is a smell and a fragile pattern. If a dev forgets to call these, the window is broken.
1. No guard for multiple windows if `visual_resources_editor_window` is freed externally.

## `core/bulk_editor.gd`
**Class**: `BulkEditor`.

1. `signal error_occurred`, `signal resources_edited`.

1. `func _ready()`
1. Hooks global editor inspector `property_edited`.
1. It never checks if the inspector already has listeners or is used by other tools.

1. `func _exit_tree()`
1. Clears bulk proxy and disconnects. Good.

1. `func _clear_bulk_proxy()`
1. Sets `_bulk_proxy` to null and calls `EditorInterface.inspect_object(null)`.
1. This nukes the inspector selection, even if the user was inspecting something else. Harsh UX.

1. `func _create_bulk_proxy()`
1. Builds proxy resource, assigns values from selected resource if only one is selected.
1. If multiple resources with different scripts, uses `current_class_script` as fallback.
1. Uses editor inspector to show proxy.

1. `func _get_common_script()`
1. Compares scripts across selected resources; returns `current_class_script` if mismatch.
1. If `current_class_script` is null (possible during race), bulk edit silently does nothing.

1. `func _on_inspector_property_edited(property)`
1. If the edited object is `_bulk_proxy`, it sets the same property on all resources and saves each.
1. Calls `ResourceSaver.save` directly per resource.
1. Emits error message containing only paths.
1. `EditorInterface.get_resource_filesystem().scan_sources()` after each edit. Heavy.

**Harsh notes**
1. **No Undo/Redo**. This is the biggest UX failure of the entire tool.
1. If `property not in res` is wrong for `Resource`, the whole bulk edit silently fails or partially applies.
1. Saving per resource in a loop will be slow for large selections and will freeze the editor.
1. No batch error recovery. Partial saves leave the dataset in a half-updated state.

## `core/state_manager.gd`
**Class**: `VREStateManager`.

1. `func _ready()`
1. Early exit if not in editor.
1. Builds maps and class list.
1. Connects filesystem and script class update signals.

1. `func _exit_tree()`
1. Disconnects signals. Good.

1. `func set_class(class_name_str)`
1. Sets `_current_class_name` and triggers full refresh.

1. `func set_include_subclasses(value)`
1. Sets flag and refreshes.

1. `func select(resource, ctrl_held, shift_held)`
1. Implements selection + range selection and updates anchors.
1. Emits cloned selection list.

1. `func next_page()` / `func prev_page()`
1. Updates `_current_page` and emits page data.

1. `func refresh_resource_list_values()`
1. Resolves classes, scans properties, scans resources, restores selection, resets page, emits data.
1. Synchronous full scan every time.

1. `func _resolve_current_classes()`
1. Computes current class set with or without subclasses.
1. Loads script for base class only.

1. `func _scan_properties()`
1. For each class, reads script properties and unions them.
1. `columns` is union of all properties across class set.

1. `func _scan_resources()`
1. Scans the filesystem for `.tres` resources and loads them all.
1. Builds `_known_resource_mtimes` after load.

1. `func _restore_selection()`
1. Rehydrates selection using paths. Good.

1. `func _rescan_resources_only()`
1. Differential scan using mtimes. Good idea.
1. Reloads modified resources in place.
1. Sorts resources and emits paged data.

1. `func _on_script_classes_updated()`
1. Sets a pending flag and uses debounce timer to call `_handle_classes_updated`.
1. `print` calls left in production code.

1. `func _handle_classes_updated()`
1. Rebuilds class maps and recalculates class list.
1. Tries to detect removed classes and re-save resources.
1. Emits class change signals.
1. Handles current class rename via `current_class_renamed`.
1. Handles property changes by re-saving resources.

1. `func _resave_orphaned_resources()`
1. Re-saves resources for classes that no longer exist.
1. No error handling or validation.

1. `func _detect_class_rename()`
1. Uses script path equivalence to guess rename. Works only for script renames in place.

1. `func _handle_property_changes()`
1. If properties change, re-scans and re-saves all resources.
1. This is destructive and can mutate file ordering or formatting.

1. `func _on_filesystem_changed()`
1. Debounced rescan for non-class-change filesystem updates.

**Harsh notes**
1. `refresh_resource_list_values` is likely to freeze the editor on large projects.
1. `ProjectClassScanner` only checks `.tres` and ignores `.res`, which is arbitrary and inconsistent.
1. `print` statements should not be in released tooling.
1. Calling `ResourceSaver.save` on property schema change mutates every resource file without confirmation. That is very risky behavior.

## `core/project_class_scanner.gd`
**Class**: `ProjectClassScanner` (static).

1. `get_project_resource_classes()`
1. Filters project global classes down to descendants of `Resource`.
1. Skips `addons/` by path.

1. `build_global_classes_map()` / `build_project_classes_parent_map()`
1. Wrappers around `ProjectSettings.get_global_class_list()`.

1. `class_is_resource_descendant()`
1. Recursively walks class inheritance.
1. Falls back to `ClassDB.is_parent_class()` if base is native.

1. `get_descendant_classes()`
1. Recursively returns descendants.
1. Uses recursion with no guard against cycles. Probably fine, but risky if class graph is bad.

1. `scan_folder_for_classed_tres_paths()`
1. Recurses filesystem and parses `.tres` to find `script_class`.
1. Skips `res://addons/` entirely.

1. `get_class_from_tres_file()`
1. Reads only the first line, assumes `script_class` is there. This is fragile.

1. `get_properties_from_script_path()`
1. Reads `get_script_property_list` and filters for editor-visible props.
1. Omits `resource_`, `metadata/`, and a hardcoded list.

1. `unite_classes_properties()`
1. Builds a union of property dictionaries across class list.

1. `load_classed_resources_from_dir()`
1. Scans paths and loads each resource with cache replace.

**Harsh notes**
1. `get_class_from_tres_file()` is a correctness landmine. If the first line is not the script class, resource will be ignored.
1. There is no caching; full scans re-parse and reload everything.
1. No error reporting for failed loads or parse errors.

## `ui/visual_resources_editor_window.gd`
**Class**: `VisualResourcesEditorWindow`.

1. `create_and_add_dialogs()`
1. Manually instantiates dialogs and adds them as children. This is a workaround for @tool window issues.

1. `connect_components()`
1. Manually connects all signals. This is not in `_ready()`, which makes lifecycle fragile.

1. `_unhandled_input()`
1. Closes window on `ui_cancel`. OK.

1. `_on_class_selected()`
1. Updates state manager and bulk editor current class context.
1. Updates dialog context.

1. `_on_include_subclasses_toggled()`
1. Updates state and warning label.

1. `_on_project_classes_changed()`
1. Updates class selector dropdown.

1. `_on_state_data_changed()`
1. Sends resource list data to UI.

1. `_on_selection_changed()`
1. Updates bulk editor and UI selection.

1. `_on_resources_edited()`
1. Refreshes the rows for edited resources.

1. `_on_close_requested()`
1. `queue_free()` on window.

**Harsh notes**
1. Manual lifecycle is error-prone. If a refactor forgets to call `connect_components()`, everything breaks silently.
1. `BulkEditor` and `VREStateManager` are hard-wired to UI, no abstraction or test seam.

## `ui/resource_list/resource_list.gd`
**Class**: `ResourceList`.

1. `_ready()`
1. Wires toolbar buttons to signals.

1. `set_data(resources, columns)`
1. Rebuilds rows and updates status.

1. `refresh_row(resource_path)`
1. Linear search to update a single row.

1. `update_selection(selected)`
1. Updates selection state on each row.

1. `update_pagination_bar()`
1. Updates pagination controls.

1. `_build_rows()` / `_clear_rows()`
1. Creates and destroys all rows each refresh.
1. Does not reuse nodes.

1. `_on_resource_row_selected()`
1. Forwards selection to state manager.

1. `_on_row_delete_requested()` / `_on_delete_selected_pressed()`
1. Emit delete request with paths.

**Harsh notes**
1. The entire list is destroyed and rebuilt on every data change, which is fine for small sets but will be bad for large lists.
1. `_resource_to_row` is dead data; never used.

## `ui/resource_list/resource_row.gd`
**Class**: `ResourceRow`.

1. `_ready()`
1. Sets file label and builds fields.

1. `_build_field_labels()`
1. Determines property ownership via script property list.
1. Creates separators and labels for each column.

1. `update_display()`
1. Updates label values for owned columns.

1. `set_selected()`
1. Toggles button pressed state.

1. `_set_label_value()`
1. Formats values, updates label text and tooltip.
1. Special handling for `Color` types, changes style box background.

1. `_format_value()`
1. String formatting for common types.

1. `_on_pressed()`
1. Emits selection with ctrl/shift modifiers.

1. `_on_delete_pressed()`
1. Emits delete signal.

**Harsh notes**
1. `label.get_theme_stylebox("normal")` is potentially shared; mutating it may affect other labels. You should `duplicate()` before modifying.
1. No truncation or width management for long values; UI will look messy on large strings.

## `ui/dialogs/save_resource_dialog.gd`
**Class**: `SaveResourceDialog`.

1. `_ready()`
1. Configures file dialog.

1. `show_create_dialog()`
1. Requires a class selection, pulls script path, pops dialog.

1. `_on_file_selected(path)`
1. Loads class script, instantiates resource, saves to path.
1. No undo/redo, no post-save refresh.

**Harsh notes**
1. `global_classes_map` must be injected externally. If not set, dialog silently fails.

## `ui/dialogs/confirm_delete_dialog.gd`
**Class**: `ComfirmDeleteDialog`.

1. `_ready()`
1. Connects `confirmed`.

1. `show_delete_dialog(paths)`
1. Populates dialog text with filenames.

1. `_on_confirmed()`
1. Removes files with `DirAccess.remove_absolute`.
1. Guard against paths outside `res://` is good.
1. Updates filesystem entries.

**Harsh notes**
1. No undo/redo. This is destructive.
1. Uses `update_file()` but does not trigger a rescan if a folder disappears or paths are stale.

## `ui/dialogs/error_dialog.gd`
**Class**: `ErrorDialog`.

1. `show_error(message)`
1. Sets dialog text and shows popup. Fine.

## `ui/class_selector/class_selector.gd`
**Class**: Class selector UI.

1. `_ready()`
1. Calls `set_classes_in_dropdown` even if list is empty.

1. `set_classes_in_dropdown()`
1. Clears dropdown and repopulates with sorted class names.
1. Keeps previous selection if possible.

1. `set_classes()`
1. Updates internal list and refreshes dropdown.

1. `select_class()`
1. Selects class in dropdown if present.

1. `_on_class_dropdown_item_selected()`
1. Emits `class_selected` when user picks item.

**Harsh notes**
1. Uses `_classes_names` (typo) which isn’t a big deal but indicates weak naming discipline.

**Cross-Cutting Architectural Issues**
1. **No Undo/Redo anywhere.** For editor tooling, this is a showstopper for user trust.
1. **Monolithic state manager.** `VREStateManager` owns scanning, selection, paging, and schema sync. This is too much for a single class and makes testing difficult.
1. **Tight coupling to Editor API.** `BulkEditor` and state manager hardcode `EditorInterface` usage, making them hard to reuse or test.
1. **Synchronous, blocking scans.** Scanning and loading resources synchronously will hang the editor in larger projects.
1. **Fragile data model.** Resource detection depends on file format details. Not robust.

**Concrete Recommendations (If You Want It Fixed)**
1. Add `UndoRedo` for bulk edits and deletions.
1. Replace `.tres` first-line parsing with a safe parser or `ResourceLoader` metadata read.
1. Move scanning to a background thread or use deferred calls with progress feedback.
1. Split `VREStateManager` into smaller components (class scanning, resource indexing, selection/paging).
1. Add explicit error reporting for resource load failures and display them in `ErrorDialog`.

