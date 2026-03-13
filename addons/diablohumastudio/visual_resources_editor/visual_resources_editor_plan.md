# Visual Resources Editor — Implementation Plan

## M1 — Include/Exclude Folder Filters (UI + Logic)

Goal: Add UI fields to include/exclude folders and make `ProjectClassScanner.get_resource_classes_in_folder()` respect them.

Planned changes:
1. UI (`addons/diablohumastudio/visual_resources_editor/ui/visual_resources_editor_window.tscn`)
   - Add two `TextEdit` nodes to the TopBar (or a small VBox next to `IncludeSubclassesCheck`).
   - Unique names: `IncludeFoldersTextEdit`, `ExcludeFoldersTextEdit`.
   - Placeholder text:
     - Include: `Include folders (comma-separated, res://...)`
     - Exclude: `Exclude folders (comma-separated, res://...)`
   - Keep them compact with `custom_minimum_size` and `size_flags_horizontal = SIZE_EXPAND_FILL`.

2. Window script (`addons/diablohumastudio/visual_resources_editor/ui/visual_resources_editor_window.gd`)
   - Add helpers:
     - `_parse_folder_list(text: String) -> Array[String]` that splits by comma, trims, and drops empties.
     - `_get_include_folders() -> Array[String]` and `_get_exclude_folders() -> Array[String]`.
   - On `text_changed` of either `TextEdit`, call `%VREStateManager.set_folder_filters(include, exclude)`.

3. State manager (`addons/diablohumastudio/visual_resources_editor/core/state_manager.gd`)
   - Add fields:
     - `_include_folders: Array[String] = []`
     - `_exclude_folders: Array[String] = []`
   - Add `set_folder_filters(include: Array[String], exclude: Array[String]) -> void` to store and `rescan()`.
   - Pass include/exclude to `ProjectClassScanner.get_resource_classes_in_folder()`.

4. Scanner (`addons/diablohumastudio/visual_resources_editor/core/project_class_scanner.gd`)
   - Implement include/exclude logic:
     - If `included_folder_paths` is non-empty, only accept classes whose `path` starts with any of these.
     - If `excluded_folder_paths` is non-empty, reject classes whose `path` starts with any of these.
   - Normalize paths to ensure they end with `/` when matching.

## M2 — Scan Performance Plan

Goal: Avoid full project scans on every change.

Planned changes:
1. Build an index map:
   - `var _tres_class_index: Dictionary = { path: class_name }`.
2. On startup or when class filter changes:
   - Populate index once by scanning `EditorFileSystemDirectory` and storing for `.tres` files.
3. On `filesystem_changed`:
   - Use `EditorFileSystem` to get changed files (or re-scan only the changed directories).
   - Update only the changed entries in `_tres_class_index`.
4. `scan_folder_for_classed_tres()` becomes:
   - a fast filter over the indexed dictionary:
     - return `[path for path in _tres_class_index.keys() if _tres_class_index[path] in classes]`.

Implementation detail:
- If `EditorFileSystem` does not provide changed paths reliably, fallback to a partial re-scan of the project root only when the debounce fires, but cache the class of each `.tres` to avoid repeated `ResourceLoader.load` per file.

## M7 — Avoid Class Selector Reset On Data Changes

Goal: Keep the selected class stable and only rebuild the dropdown when the class list changes.

Planned changes:
1. Add a cached list in window script:
   - `var _last_class_names: Array[String] = []`.
2. Update `_refresh_class_selector()`:
   - Compute `names`.
   - If `names == _last_class_names`, return early.
   - Preserve current selection:
     - `var current: String = %VREStateManager.get_current_class_name()` (add getter in state manager).
   - Update dropdown, then re-select `current` if it still exists.
   - Store `names` in `_last_class_names`.

## M8 — Proper GUI Input For Multi-Select

Goal: Use event modifiers instead of global input state.

Planned changes:
1. ResourceRow (`addons/diablohumastudio/visual_resources_editor/ui/resource_list/resource_row.gd`)
   - Override `_gui_input(event: InputEvent)`.
   - If `event is InputEventMouseButton` and `event.pressed` and `event.button_index == MOUSE_BUTTON_LEFT`, emit:
     - `resource_row_selected.emit(resource, event.shift_pressed)`.
2. Optionally add `ctrl_pressed` if we decide to support Ctrl toggling:
   - Extend signal signature to `signal resource_row_selected(resource: Resource, shift_held: bool, ctrl_held: bool)`.
   - Update `ResourceList` selection logic accordingly.

## M9 — Resource As Dictionary Key (Why It’s A Problem + Fix)

Why it’s a problem:
- Resources are object references; reloading resources produces new instances, so dictionary lookups fail.
- Using resources as keys can keep them alive unintentionally (hard references), increasing memory usage.
- It also breaks if two different resources represent the same file path.

Planned fix:
1. Replace `_resource_to_row: Dictionary` to map `resource_path: String` → `ResourceRow`.
2. Update `_build_rows()` to use `row.resource_path` as key.
3. Update selection logic to use paths rather than object identity.

## L1 — Warning Label Alternative (Proposal)

Goal: Replace unclear warning text with something explicit and context-aware.

Planned changes:
1. Text proposal:
   - `Warning: String-path inheritance is not supported.`
2. Show only when `IncludeSubclassesCheck` is enabled:
   - Connect `toggled` to show/hide `%SubclassWarningLabel`.

## Todo For Later

- C1: Undo/redo for file deletion (leave for later).
- MF1: Keyboard navigation (leave for later).
- MF2: Search/filter (leave for later).
