# Visual Resources Editor — Unified Fix List

All items from the three reviews (Claude, Gemini, Codex) merged. Duplicates unified. Conflicts and corrections noted.

---

## Items

### 1. `get_class_from_tres_file()` loads entire resource — performance

**Creator**: Gemini + Codex (Claude noted only the silent failure aspect)
**Severity**: CRITICAL
**File**: `core/project_class_scanner.gd`
**Solved**: yes

~~**Problem**: Uses `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` for every `.tres` file during scans. Loads full resources with all dependencies (textures, audio, etc.) just to read the script class name. Freezes editor on medium+ projects.~~

~~**Fix (Gemini)**: Read `.tres` as plain text with `FileAccess`, parse header with RegEx to find `script_class` or `ExtResource` script reference.~~
~~**Fix (Codex)**: Parse `.tres` text for `script = ExtResource` and map to class without fully loading; or cache results and only load on demand.~~

~~**problem_claude_correction**: Problem is real and severe. Both Gemini and Codex correctly identified it.~~
~~**fix_claude_correction**: Both fixes are directionally correct. Prefer Codex's approach: parse the `.tres` header text for the `[ext_resource ... type="Script"]` and `script = ExtResource(...)` lines, then map the script path to a class name via the already-cached `_global_classes_map`. This avoids RegEx fragility while still avoiding full loads. Must handle binary `.tres` files gracefully (skip them or fall back to load).~~

**Fix applied**: Read first line of `.tres` with `FileAccess`, search for `script_class="` to extract class name without loading the resource.

---

### 2. Silent failure when load returns null

**Creator**: Claude
**Severity**: HIGH
**File**: `core/project_class_scanner.gd` — `get_class_from_tres_file()` lines 89-94
**Solved**: yes (item 1 fix eliminates the load call entirely)

~~**Problem**: When `ResourceLoader.load()` returns null (corrupt file, missing script), the function silently returns `""`. Resource vanishes from list with no warning.~~

~~**Fix**: Add `push_warning("VRE: Failed to load resource at '%s'" % tres_file_path)` before returning empty.~~

---

### 3. Invalid/fragile Array syntax

**Creator**: Gemini + Claude
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — `get_descendant_classes()`
**Solved**: not an error

~~**Problem (Gemini)**: `Array([], TYPE_STRING, "", null)` is "invalid Godot 4 syntax".~~
~~**Problem (Claude)**: Same line — fragile and hard to read.~~

~~**problem_claude_correction**: Gemini is wrong that it's "invalid syntax" — `Array([], TYPE_STRING, "", null)` IS valid Godot 4 typed array constructor. It compiles and runs. But it IS fragile and unreadable.~~
~~**Fix**: Replace with simple `var descendants: Array[String] = []` then conditionally `append(base_class)`.~~

This is the only way to create an empty typed dict in one line. Using `as` only works for individual elements.

---

### 4. O(N^2) map building — uncached `get_global_class_list()`

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `core/project_class_scanner.gd`
**Solved**: yes

~~**Problem**: Multiple functions iterate over `ProjectSettings.get_global_class_list()` independently instead of sharing a single cached result.~~

~~**Fix**: Call `get_global_class_list()` once per filesystem change, cache the parsed maps. StateManager already calls `_set_maps()` in `rescan()`, so ensure all downstream code uses the cached maps, not fresh API calls.~~

~~**Conflicting**: Item #22 (BulkEditor also calls `get_global_class_list()` independently).~~

**Fix applied**: `_global_clases_map` only changes in `_on_script_classes_updated()`. Window passes it down to `SaveResourceDialog` and `BulkEditor` so they don't call `get_global_class_list()` independently.

---

### 5. Reference type mutation in bulk proxy

**Creator**: Gemini
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_create_bulk_proxy()` line 35
**Solved**: yes

~~**Problem**: `_bulk_proxy.set(prop.name, edited_resources[0].get(prop.name))` copies references for Array/Dictionary types. Editing an Array in the bulk proxy mutates the first resource's Array directly, bypassing save logic.~~

~~**Fix**: Deep-duplicate reference types:~~
~~```gdscript~~
~~var value: Variant = edited_resources[0].get(prop.name)~~
~~if value is Array or value is Dictionary:~~
~~    value = value.duplicate(true)~~
~~_bulk_proxy.set(prop.name, value)~~
~~```~~

**Fix applied**: Single selection copies values from the resource into the proxy. Multi-selection uses default values (0, "", [], etc.) so editing applies a clean value to all.

---

### 6. Cached EditorInspector reference goes stale

**Creator**: Claude
**Severity**: CRITICAL
**File**: `core/bulk_editor.gd` — line 13
**Solved**: yes

~~**Problem**: `var _inspector: EditorInspector = EditorInterface.get_inspector()` cached at member level. If editor layout changes, reference becomes stale, signal connections silently stop.~~

~~**Fix**: Fetch fresh inspector in `_ready()` and re-fetch when needed. Don't cache at declaration time.~~

**Fix applied**: Fetch fresh inspector in `_ready()` instead of caching at declaration.

---

### 7. Missing bulk proxy cleanup / inspector not cleared on empty selection

**Creator**: Claude + Codex
**Severity**: CRITICAL
**File**: `core/bulk_editor.gd`
**Solved**: yes

~~**Problem (Claude)**: `_bulk_proxy` is never freed. Old proxies accumulate in memory.~~
~~**Problem (Codex)**: When user deselects all rows, inspector still shows stale proxy.~~

~~**Fix**: Add `_clear_bulk_proxy()` that sets `_bulk_proxy = null` and calls `EditorInterface.inspect_object(null)`. Call it at start of `_create_bulk_proxy()` and when `edited_resources` becomes empty.~~

**Fix applied**: Added `_clear_bulk_proxy()`. Called at start of `_create_bulk_proxy()` and when `edited_resources` is empty.

---

### 8. BulkEditor applies properties to resources that don't have them

**Creator**: Codex
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_on_inspector_property_edited()` line 53
**Solved**: yes

~~**Problem**: `res.set(property, new_value)` is called blindly on all selected resources. In subclass mode, a property from `Sword` gets set on a `Bow` resource, polluting it with unintended values.~~

~~**Fix**: Check property exists before setting:~~
~~```gdscript~~
~~var res_props: Array = res.get_property_list()~~
~~var has_prop: bool = false~~
~~for p: Dictionary in res_props:~~
~~    if p.name == property:~~
~~        has_prop = true~~
~~        break~~
~~if has_prop:~~
~~    res.set(property, new_value)~~
~~```~~

~~**fix_claude_correction**: The fix works but is O(N*M). Better: build a `Dictionary` of property names once per resource script and check with `.has()`. Or even simpler — cache the owned properties set per class_name since it doesn't change between edits.~~

**Fix applied**: `if property not in res: continue` — skips resources that don't have the property.

---

### 9. Partial save emits full success

**Creator**: Claude
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_on_inspector_property_edited()` lines 51-59
**Solved**: yes

~~**Problem**: If `ResourceSaver.save()` fails for some resources, `resources_edited` signal is emitted with ALL resources (including failed ones). UI refreshes as if everything succeeded.~~

~~**Fix**: Only emit successfully saved resources in the signal.~~

**Fix applied**: `resources_edited` now only emits successfully saved resources. Error shows failed paths (max 3).

---

### 10. O(N) script lookup in BulkEditor

**Creator**: Gemini
**Severity**: LOW
**File**: `core/bulk_editor.gd` — `_get_current_class_script()` lines 39-43
**Solved**: yes

~~**Problem**: Iterates `get_global_class_list()` every time a property is edited to find the current class script.~~

~~**Fix**: Cache the script reference when `current_class_name` is set.~~

~~**Conflicting**: Item #4 (same root cause — uncached class list).~~

**Fix applied**: `current_class_script`, `current_class_property_list`, and `subclasses_property_lists` cached in StateManager on rescan, passed to BulkEditor from window. BulkEditor uses cached property lists instead of `get_script_property_list()`. `_get_current_class_script()` removed from BulkEditor. Multi-select of same subclass uses that subclass's script via `_get_common_script()`.

---

### 11. Naive error handling — UI overflow

**Creator**: Gemini
**Severity**: LOW
**File**: `core/bulk_editor.gd` — line 58
**Solved**: yes

~~**Problem**: If 50 resources fail to save, the error string overflows the popup.~~

~~**Fix**: Limit error output to first 5-10 paths and append "... and X more".~~

**Fix applied**: Error shows first 3 failed paths + "... and N more" if there are more.

---

### 12. Bulk edit saves on every property edit, no undo/redo

**Creator**: Codex
**Severity**: HIGH
**File**: `core/bulk_editor.gd`
**Solved**: unwanted

~~**Problem**: Every single property edit triggers immediate save of all selected resources with no UndoRedo support. Destructive UX.~~

~~**Fix (Codex)**: Use `EditorUndoRedoManager` to register changes. Debounce/batch saves.~~

~~**problem_claude_correction**: Problem is real. However, CLAUDE.md explicitly states: "Bulk edit undo/redo is optional; do not block work on adding it unless explicitly requested." This is a known accepted trade-off, not a forgotten bug. Debouncing saves IS worth doing though.~~

---

### 13. Premature initialization in StateManager

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `core/state_manager.gd` — line 15
**Solved**: yes

~~**Problem**: `var project_resource_classes: Array[String] = ProjectClassScanner.get_resource_classes_in_folder()` executes heavy I/O at object instantiation (during `_init`), before `_ready()`.~~

~~**Fix**: Initialize as empty array, populate in `_ready()`.~~

**Fix applied**: Initialized as empty array, populated in `_ready()` after `_set_maps()`.

---

### 14. Typo: double space in timer disconnect

**Creator**: Gemini
**Severity**: LOW
**File**: `core/state_manager.gd` — line 39
**Solved**: yes

~~**Problem**: `if  %RescanDebounceTimer` has double space.~~

~~**Fix**: Remove extra space.~~

~~**problem_claude_correction**: The double space is cosmetic and doesn't affect behavior. Valid but trivial.~~

**Fix applied**: Debouncer is now its own node with internal signal connections; the old disconnect code no longer exists.

---

### 15. Unnecessary getters without return types

**Creator**: Gemini
**Severity**: LOW
**File**: `core/state_manager.gd` — lines 70-77
**Solved**: yes

~~**Problem**: `get_class_names()`, `get_columns()`, `get_resources()` have no return types and just return public vars.~~

~~**Fix**: Either add return types or remove the getters entirely (vars are already public).~~

~~**problem_claude_correction**: Partially valid. The vars `columns` and `resources` are public, so getters are redundant. But `_current_class_names` is private, so `get_class_names()` provides access — that getter is useful. Fix should be: add return types to all, keep `get_class_names()`, consider removing the others.~~

**Fix applied**: Deleted all three getters. Renamed `_current_class_names` to `current_class_names` (public).

---

### 16. Missing empty-class validation in rescan

**Creator**: Claude
**Severity**: HIGH
**File**: `core/state_manager.gd` — `rescan()` lines 60-62
**Solved**: yes

~~**Problem**: If `_get_included_classes()` returns empty (deleted class, corrupt parent map), columns and resources are silently empty. UI shows "0 resources" with no explanation.~~

~~**Fix**: Check and `push_warning()` when class name is set but resolution returns empty.~~

**Fix applied**: Added early return with `push_warning()` when `current_class_names` is empty after `_get_included_classes()`.

---

### 17. Full project re-scan on any filesystem change (no incremental updates)

**Creator**: Codex
**Severity**: CRITICAL
**File**: `core/state_manager.gd`, `core/project_class_scanner.gd`
**Solved**: solved

~~**Problem**: Every `filesystem_changed` triggers debounce then full recursive scan + load of all `.tres` files. Falls over on medium/large projects.~~

~~**Fix**: Build a cached index `path -> class_name`, update incrementally on changes. Use `EditorFileSystem` APIs to detect which files changed. Only reload changed files.~~

~~**problem_claude_correction**: Problem is real and will become severe at scale. However, the current debounce timer already mitigates rapid-fire rescans. The fix is architecturally correct but is a significant refactor — should be planned as a dedicated phase, not a quick fix.~~

---

### 18. Class list change detection is order-sensitive

**Creator**: Codex
**Severity**: MEDIUM
**File**: `core/state_manager.gd` — `_check_project_classes_changed()` line 88
**Solved**: yes

~~**Problem**: `new_classes == project_resource_classes` compares arrays directly. If order changes but set is identical, it triggers unnecessary UI refresh.~~

~~**Fix**: Sort both arrays before comparing, or compare as sets.~~

~~**problem_claude_correction**: Looking at the code, `get_resource_classes_in_folder()` returns classes from `get_global_class_list()` which has a stable order. And `set_classes_in_dropdown()` sorts alphabetically anyway. So the order instability is unlikely in practice. Low-risk fix but not urgent.~~

**Fix applied**: `_check_project_classes_changed()` no longer exists. Class list updates now trigger directly from `script_classes_updated` signal — no comparison needed.

---

### 19. EditorFileSystemDirectory traversal during rescan

**Creator**: Claude
**Severity**: CRITICAL
**File**: `core/state_manager.gd` — `rescan()` line 64
**Solved**: yes

~~**Problem**: `get_filesystem()` returns a reference Godot frees on every `scan()`. If rescan triggers mid-traversal, reference becomes freed → crash.~~

~~**Fix**: Guard with `is_instance_valid(root)` checks during traversal.~~

**Fix applied**: `scan_folder_for_classed_tres_paths()` now checks `is_instance_valid(dir)` alongside the null check (covers every recursive subdir call). `rescan()` validates `root` with `is_instance_valid()` before passing it to the traversal, with a `push_warning()` on failure.

---

### 20. Dictionary `.has()` doesn't deduplicate by content

**Creator**: Claude
**Severity**: HIGH
**File**: `core/project_class_scanner.gd` — `unite_classes_properties()`
**Solved**: not an error

~~**Problem**: `properties.has(prop)` compares Dictionary references, not content. Duplicate columns accumulate.~~

~~**Fix**: Track by property name in a separate `Dictionary[String, bool]` and check `.has(prop.name)`.~~

**problem_claude_correction**: In GDScript 4, `Dictionary` equality uses deep value comparison, not reference comparison. So `properties.has(prop)` correctly deduplicates identical property dictionaries. The stated problem is wrong. The only theoretical edge case — same property name but different type/hint across subclasses — is extremely unusual. Not an error.

---

### 21. Property usage filter mismatch between scanner and row

**Creator**: Codex
**Severity**: HIGH
**File**: `core/project_class_scanner.gd`, `ui/resource_list/resource_row.gd`
**Solved**: yes

~~**Problem**: `unite_classes_properties()` filters properties by `PROPERTY_USAGE_EDITOR`, but `ResourceRow._build_field_labels()` uses `get_script_property_list()` to build `owned` dict WITHOUT the same filter. A property excluded from columns could still appear as "owned", or vice versa.~~

~~**Fix**: Apply the same `PROPERTY_USAGE_EDITOR` filter in `_build_field_labels()` when building the `owned` dictionary.~~

**Fix applied**: `_build_field_labels()` now applies the same `PROPERTY_USAGE_EDITOR` check plus the same `resource_*`, `metadata/`, `script`, `resource_local_to_scene` exclusions used by `get_properties_from_script_path()`. Also replaced `range()` with direct size iteration.

---

### 22. O(N) lookup in SaveResourceDialog

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/dialogs/save_resource_dialog.gd`
**Solved**: yes

~~**Problem**: `_get_class_script_path()` does its own full pass over `ProjectSettings.get_global_class_list()` instead of using the centralized cache.~~

~~**Fix**: Accept the script path as a parameter or use the cached maps from StateManager/ProjectClassScanner.~~

~~**Conflicting**: Item #4, #10 (same root cause).~~

**Fix applied**: `_get_class_script_path()` already iterates `global_classes_map` which is set from `%VREStateManager.global_clases_map` in `_on_class_selected()`. It does NOT call `get_global_class_list()` independently. Items #4 and #10 already resolved the root cause.

---

### 23. SaveResourceDialog doesn't debounce scan

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/dialogs/save_resource_dialog.gd` — line 40
**Solved**: yes

~~**Problem**: Calls `EditorInterface.get_resource_filesystem().scan()` directly. Multiple rapid saves trigger independent scans, uncoordinated with StateManager's debounce timer.~~

~~**Fix**: Remove `scan()` call. Let `filesystem_changed` propagate naturally through StateManager's debounce.~~

**Fix applied**: Removed `EditorInterface.get_resource_filesystem().scan()` call from `_on_file_selected()`. The `filesystem_changed` signal fires naturally when the file is written to disk, flowing through StateManager's debounce timer.

---

### 24. No overwrite warning on save

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/dialogs/save_resource_dialog.gd`
**Solved**: not a problem

~~**Problem**: Saving a new resource can overwrite an existing file with no warning.~~

~~**Fix**: Check `FileAccess.file_exists(target_path)` and show confirmation dialog before overwriting.~~

**problem_claude_correction**: `EditorFileDialog` with `FILE_MODE_SAVE_FILE` already shows a built-in overwrite confirmation when the selected filename matches an existing file. No custom dialog needed.

---

### 25. Signal connection leak in ResourceList

**Creator**: Claude
**Severity**: CRITICAL
**File**: `ui/resource_list/resource_list.gd` — `_clear_rows()` lines 57-62
**Solved**: yes

~~**Problem**: Rows freed via `queue_free()` but signal connections (`resource_row_selected`, `delete_requested`) never disconnected. Signal could fire between `queue_free()` and actual deletion.~~

~~**Fix**: Disconnect signals before freeing each row.~~

**Fix applied**: `_clear_rows()` now disconnects `resource_row_selected` and `delete_requested` from each valid row before calling `queue_free()`.

---

### 26. Null pointer crash in ResourceList selection

**Creator**: Claude
**Severity**: CRITICAL
**File**: `ui/resource_list/resource_list.gd` — lines 71, 74, 81
**Solved**: yes

~~**Problem**: `_resource_to_row[resource].set_selected()` called without checking key exists or row is valid. Crashes if resource deleted while selected.~~

~~**Fix**: Guard with `_resource_to_row.has(resource) and is_instance_valid(...)`.~~

**Fix applied**: All `_resource_to_row[resource]` accesses in `_on_resource_row_selected()` are now guarded with `_resource_to_row.has(resource) and is_instance_valid(_resource_to_row[resource])`. Parameter renamed from `shift_held` to `ctrl_held` (see item 27).

---

### 27. Ctrl/Cmd-click for toggle (was: Shift-click is toggle, not range select)

**Creator**: Gemini + Codex
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`, `ui/resource_list/resource_row.gd`
**Solved**: yes

~~**Problem (both)**: Shift toggles individual items. Standard UX: Shift = range select, Ctrl/Cmd = toggle.~~

~~**Fix**: Track `_last_selected_index`. Shift+click selects all rows between last and current. Use Ctrl/Cmd for toggle.~~

**Fix applied**: Multi-select modifier changed from Shift to Ctrl/Cmd (KEY_CTRL or KEY_META). Signal `resource_row_selected` parameter renamed `shift_held` → `ctrl_held`. Range select (Shift) deferred to item 27b.

---

### 27b. Shift-click range select

**Creator**: Gemini + Codex
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`, `ui/resource_list/resource_row.gd`, `core/state_manager.gd`
**Solved**: yes

~~**Problem**: Shift+click should range-select all rows between last selected and current. Not yet implemented.~~

~~**Fix**: Track `_last_selected_index`. Shift+click selects all rows between last and current index.~~

**Fix applied**: Selection state moved entirely to `VREStateManager`. `StateManager.select(resource, ctrl_held, shift_held)` owns `selected_resources`, `_selected_paths`, and `_last_anchor` (a global index into `resources[]`). Shift+click computes `[min(anchor, current)..max(anchor, current)]` over the full resource list — so range selection works correctly across pagination pages. The anchor stays fixed on repeated Shift+clicks. `resource_row.gd` emits `shift_held` via `Input.is_key_pressed(KEY_SHIFT)`. `resource_list.gd` forwards the click to `row_clicked` signal with no state of its own. `visual_resources_editor_window.gd` wires `row_clicked → StateManager.select` and `StateManager.selection_changed → ResourceList.update_selection`.

---

### 28. Shift detection via `Input.is_key_pressed(KEY_SHIFT)` is unreliable

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 119
**Solved**: not a problem

~~**Problem**: Checks global keyboard state at signal fire time. If Shift released slightly before mouse button, detection fails.~~

~~**Fix**: Override `_gui_input(event)` and check `event.shift_pressed` on `InputEventMouseButton`.~~

**problem_claude_correction**: `Input.is_key_pressed()` polls at signal emission time, which is the same frame as the click. In practice this works reliably in editor tools. Using `Input.is_key_pressed` is the correct and idiomatic approach here. Not a problem.

---

### 29. Stale resource references after rescan

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`
**Solved**: yes

~~**Problem**: `selected_rows` stores `Resource` instances. After rescan, resources may be reloaded as new objects, breaking selection state.~~

~~**Fix**: Track selection by `resource_path` (String), resolve to current row after refresh.~~

**Fix applied**: Added `_selected_paths: Array[String]` that mirrors `selected_rows` by path. `set_data()` saves paths before rebuild, then restores selection for any resource whose path is still present. `_on_resource_row_selected()` maintains `_selected_paths` in sync with `selected_rows`.

---

### 30. Layout jitter from dynamic button text

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/resource_list/resource_list.gd` — line 89
**Solved**: yes

~~**Problem**: `"Delete Selected (%d)"` changes string length, causing horizontal layout shift on every selection change.~~

~~**Fix**: Set `custom_minimum_size.x` on the button, or use a separate fixed-width label for the count.~~

**Fix applied**: `custom_minimum_size = Vector2(170, 0)` set on `DeleteSelectedBtn` in `resource_list.tscn`. Wide enough for "Delete Selected (999)".

---

### 31. No virtualization in resource list

**Creator**: Codex (Claude noted as "full table rebuild")
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`, `ui/resource_list/resource_row.gd`, `core/state_manager.gd`
**Solved**: yes (pagination)

~~**Problem**: Full control row instantiated for every resource. UI freezes on large lists.~~

~~**Fix (Codex)**: Replace with `Tree` or implement row pooling/virtualization.~~

~~**problem_claude_correction**: Valid at scale. However, for the typical use case (< 100 resources of a given class), the current approach works fine. A `Tree` would also require rewriting all row rendering logic. Recommend: first implement incremental updates (skip rebuild when data unchanged), defer full virtualization until worden needed.~~

**Fix applied**: Pagination implemented with `PAGE_SIZE = 50` in `VREStateManager`. `StateManager` owns `_current_page`, `_page_count()`, `_emit_page_data()`, `next_page()`, and `prev_page()`. `rescan()` resets to page 0 and calls `_emit_page_data()` which emits `data_changed(slice, columns)` (only the current page) and `pagination_changed(page, page_count)`. `ResourceList` is now a pure UI component — `set_data()` just builds rows from whatever slice it receives, with no knowledge of the total resource count. A `PaginationBar` (hidden when ≤ PAGE_SIZE resources) was added to `resource_list.tscn` with Prev/Next buttons that emit `prev_page_requested`/`next_page_requested`, wired through the window to `StateManager.prev_page()`/`next_page()`.

---

### 32. StyleBox memory bloat in ResourceRow

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 91
**Solved**: not solved

**Problem**: `_color_style.duplicate()` called for every color cell in every row. Thousands of orphaned StyleBox resources over time.

**Fix (Gemini)**: Use a `ColorRect` instead of hacking Label's StyleBox, or reuse StyleBoxes.

**problem_claude_correction**: The problem is real. However, StyleBoxes are reference-counted Resources in Godot — when the Label is freed, its overrides are freed too. So "orphaned" is overstated. The real issue is unnecessary allocation pressure during row building. Fix is valid: a `ColorRect` behind the label is cleaner, or cache StyleBoxes per unique color.

---

### 33. Missing bounds/null checks on column access

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 51
**Solved**: yes

~~**Problem**: `columns[i].name` accessed without null check. Malformed column Dictionary crashes.~~

~~**Fix**: Validate `col.has("name")` before accessing.~~

**Fix applied**: `_build_field_labels()` now checks `columns[i].has("name")` and skips the iteration if missing.

---

### 34. ResourceRow assumes toggle_mode configured in scene

**Creator**: Codex
**Severity**: LOW
**File**: `ui/resource_list/resource_row.gd`
**Solved**: not a problem

~~**Problem**: `button_pressed` only works if `toggle_mode = true`. If scene changes, selection breaks silently.~~

~~**Fix**: Set `toggle_mode = true` defensively in `_ready()`.~~

**problem_claude_correction**: `toggle_mode` IS set in the `.tscn` scene file. The scene is the source of truth for visual configuration per project conventions. Not a problem.

---

### 35. Duplicate dropdown-building code in ClassSelector

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/class_selector/class_selector.gd` — `set_classes_in_dropdown()` and `_rebuild_dropdown_preserving_selection()`
**Solved**: yes

~~**Problem**: Nearly identical dropdown rebuild logic in two methods.~~

~~**Fix**: Extract to shared `_populate_dropdown(preserve_selection: bool)`.~~

**Fix applied**: `_rebuild_dropdown_preserving_selection()` no longer exists. `set_classes_in_dropdown()` is the single method that rebuilds the dropdown and preserves the current selection. Already resolved.

---

### 36. Redundant setter + method in ClassSelector

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/class_selector/class_selector.gd` — setter on line 7 + `set_classes()` on line 27
**Solved**: yes

~~**Problem**: Both the `_classes_names` setter and `set_classes()` do the same thing.~~

~~**Fix**: Remove one. Keep `set_classes()` as the public API and remove the setter, or keep the setter and remove `set_classes()`.~~

**Fix applied**: The `_classes_names` setter was removed. `set_classes()` is the sole public API. Already resolved.

---

### 37. Inefficient array iteration

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/class_selector/class_selector.gd`
**Solved**: yes

~~**Problem**: `for i: int in range(_classes_names.size())` instead of `for i: int in _classes_names.size()`.~~

~~**problem_claude_correction**: This is a non-issue. Both forms are equivalent in GDScript 4. `range()` is NOT slower — GDScript optimizes it identically. The `in size` form is marginally more concise but not measurably faster. Remove from fix list.~~

**Fix applied**: Replaced `range()` calls with direct `in size` form across all files. Added no-range rule to CLAUDE.md.

---

### 38. Class selector resets silently when selected class disappears

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/class_selector/class_selector.gd`
**Solved**: not a problem

~~**Problem**: If the selected class is removed from the project, dropdown falls back to placeholder silently. No warning to user.~~

~~**Fix**: Emit a signal or show a warning when the selected class disappears.~~

**problem_claude_correction**: Not a problem. When a class is deleted, the native Godot delete file confirmation dialog is the only interaction point. No additional warning in the window is necessary — the user already confirmed deletion.

---

### 39. Initialization order risk in Window

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/visual_resources_editor_window.gd` — `_ready()` lines 5-22
**Solved**: yes

~~**Problem**: `%ClassSelector.set_classes()` called before connecting to `%VREStateManager.data_changed`. If `set_classes()` triggers internal class selection, state won't sync.~~

~~**Fix**: Connect signals first, then set initial state.~~

**Fix applied**: All signal connections in `_ready()` moved before `%ClassSelector.set_classes()`. Signals are now always connected before initial state is set.

---

### 40. Global `_input` for ESC key in Window

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/visual_resources_editor_window.gd` — line 25-26
**Solved**: yes

~~**Problem**: `_input()` catches `ui_cancel` globally when window is focused, potentially intercepting other editor popups.~~

~~**Fix**: Use `_unhandled_input()` instead, or remove entirely (Window already emits `close_requested` on ESC if not exclusive).~~

**Fix applied**: Changed `_input()` to `_unhandled_input()` so ESC only closes the window if no other control has already consumed the event.

---

### 41. Missing path validation before delete

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/dialogs/confirm_delete_dialog.gd`
**Solved**: yes

~~**Problem**: `DirAccess.remove_absolute()` doesn't validate path is within project. Malformed path could delete arbitrary files.~~

~~**Fix**: Check `path.begins_with("res://")` before deleting.~~

**Fix applied**: Each path is checked with `path.begins_with("res://")` before deletion. Paths outside the project are skipped with a `push_warning()` and added to `failed_paths`. A comment explains the security intent.

---

### 42. Deleting resources is irreversible, bypasses undo

**Creator**: Codex
**Severity**: HIGH
**File**: `ui/dialogs/confirm_delete_dialog.gd`
**Solved**: unwanted

~~**Problem**: Deletion cannot be undone. Unacceptable for editor tooling.~~

~~**Fix (Codex)**: Use UndoRedo APIs or implement a recycle bin.~~

~~**problem_claude_correction**: CLAUDE.md explicitly states: "Deleting resource files does not require undo/redo; use version control for recovery." This is a deliberate design decision, not a forgotten feature. A "move to trash" approach could be nice-to-have but is not required.~~

---

### 43. Orphaned `.uid` files after delete

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/dialogs/confirm_delete_dialog.gd`
**Solved**: not an error

~~**Problem**: Deleting `.tres` files leaves behind `.uid` metadata files.~~

~~**problem_claude_correction**: This is WRONG. Per CLAUDE.md: ".tres and .tscn files do NOT create .uid sidecars — their UID is embedded in the file header." Only `.gd` scripts generate `.uid` sidecar files. Deleting a `.tres` does NOT leave orphaned `.uid` files. Remove from fix list.~~

---

### 44. Plugin typo "shubmenu"

**Creator**: Gemini
**Severity**: LOW
**File**: `visual_resources_editor_plugin.gd` — line 11
**Solved**: yes

~~**Problem**: `MainToolbarPlugin.add_toolbar_shubmenu(...)`. Typo confirmed in code. Interestingly, line 14 uses the correct `remove_toolbar_submenu`.~~

~~**Fix**: Rename to `add_toolbar_submenu` (requires fixing `MainToolbarPlugin` too).~~

**Fix applied**: Renamed `add_toolbar_shubmenu` → `add_toolbar_submenu` in `main_toolbar_plugin.gd` (definition) and in all four `*_plugin.gd` callers: `visual_resources_editor_plugin.gd`, `scenes_and_resources_resaver_plugin.gd`, `custom_scenes_runner_plugin.gd`, `database_manager_plugin.gd`.

---

### 45. Untyped Dictionary parameters

**Creator**: Claude
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — multiple functions
**Solved**: yes

~~**Problem**: `classes_parent_map: Dictionary` should be `Dictionary[String, String]` for type safety.~~

~~**Fix**: Add explicit typed Dictionary signatures.~~

**Fix applied**: `get_descendant_classes()` parameter `classes_parent_map` typed as `Dictionary[String, String]`. `unite_classes_properties()` local `class_to_path` typed as `Dictionary[String, String]`. Other parameters were already typed.

---

### 46. Typo: `_global_clases_map`

**Creator**: Claude + Codex
**Severity**: LOW
**File**: `core/state_manager.gd` — line 8
**Solved**: yes

~~**Problem**: `clases` (Spanish) instead of `classes`.~~

~~**Fix**: Rename to `_global_classes_map` everywhere.~~

**Fix applied**: Renamed `global_clases_map` → `global_classes_map` in `state_manager.gd` (member var + all usages), `project_class_scanner.gd` (function parameters in `build_project_classes_parent_map` and `unite_classes_properties`), and `visual_resources_editor_window.gd`.

---

### 47. Signal connections hidden in scenes

**Creator**: Codex
**Severity**: LOW
**Solved**: not an error

~~**Problem**: Important signal wiring split between code and `.tscn` files.~~

~~**problem_claude_correction**: This is NOT a problem. Per CLAUDE.md convention, signal connections in `.tscn` scenes are standard Godot practice. The convention explicitly says to wire signals in the scene where appropriate. Remove from fix list.~~

---

### 48. No tests for scanning or CRUD

**Creator**: Codex
**Severity**: MEDIUM
**Solved**: not solved

**Problem**: Entire plugin is untested.

**Fix**: Add editor tests for scan logic and CRUD paths.

---

### 49. Hard-coded strings and magic numbers

**Creator**: Codex
**Severity**: LOW
**Solved**: yes

~~**Problem**: Labels and sizes are hard-coded.~~

~~**Fix**: Move to constants or localization table.~~

**Fix applied**: Extracted two constants:
- `class_selector.gd`: `const PLACEHOLDER_TEXT: String = "-- Select a class --"`
- `bulk_editor.gd`: `const MAX_SAVE_ERROR_PATHS: int = 3`

Size constants (delete button width) are already in `.tscn` as `custom_minimum_size`, which is the correct place per project conventions. Error message format strings with parameters are left inline — extracting them to constants would add complexity without benefit for an internal tool.

---

### 50. `get_resource_classes_in_folder` — misleading name and redundant class list call

**Creator**: Fernando (review)
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — `get_resource_classes_in_folder()`
**Solved**: yes

~~**Problem**: Two issues in the same function:~~
~~1. The name says "in folder" but the function never searches a folder — it iterates `ProjectSettings.get_global_class_list()` and filters by `classes_parent_map`. The folder name is a lie.~~
~~2. It calls `ProjectSettings.get_global_class_list()` internally even though `StateManager` already has a cached `global_classes_map`. Every call rebuilds the class list from scratch, defeating the cache.~~

~~**Fix**: Rename to `get_project_resource_classes(global_classes_map: Array[Dictionary])`. Receive the already-built `global_classes_map` and derive `classes_parent_map` internally from it. `StateManager` passes its cached map — one source of truth, no extra `get_global_class_list()` call.~~

**Fix applied**: Renamed to `get_project_resource_classes(global_classes_map: Array[Dictionary])`. Function now receives the cached `global_classes_map`, derives `classes_parent_map` internally via `build_project_classes_parent_map()`, and iterates `global_classes_map` instead of calling `ProjectSettings.get_global_class_list()`. Both call sites in `state_manager.gd` updated to pass `global_classes_map`.

---

### 51. `class_is_resource_descendant` — parameter name obscures what it actually needs

**Creator**: Fernando (review)
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — `class_is_resource_descendant()`
**Solved**: not a problem

~~**Problem**: The function receives `classes_parent_map: Dictionary[String, String]` (class → parent). It uses it to walk the inheritance chain recursively: look up the parent of `cls_name`, then recurse on the parent. The parameter name is accurate, but when reading the call site in `get_resource_classes_in_folder`, it's not obvious why a full Dictionary is needed instead of just a class name or a simple list.~~

**problem_claude_correction**: The parameter name `base` in `get_global_class_list()` entries comes from the native Godot API (`ProjectSettings.get_global_class_list()`). The `classes_parent_map` parameter name accurately describes its purpose — a map from class to parent class used for recursive ancestor traversal. No changes needed.

---

### 52. Granular resource-change signal instead of full page rebuild on modification

**Creator**: Claude Opus (analysis of Gemini "Redundant Signals" item)
**Severity**: MEDIUM
**File**: `core/state_manager.gd`, `ui/resource_list/resource_list.gd`
**Solved**: not solved

**Problem**: `_rescan_resources_only()` already knows which resources are new/modified/deleted via mtime, but discards this info and emits `data_changed` → full table rebuild. For the common case (one resource modified externally), this destroys and recreates 50 rows when only one label needs updating.

**Fix**: Add `signal resources_modified(changed_paths: Array[String])`. In `_rescan_resources_only()`, emit it for modifications. `ResourceList` calls `refresh_row()` for each changed path. Only emit `data_changed` when rows are added/deleted (structural change).

---

### 53. StateManager does too many things — split data layer from UI state

**Creator**: Claude Opus (analysis of Gemini "Dividing the VREStateManager" item)
**Severity**: MEDIUM
**File**: `core/state_manager.gd`
**Solved**: not solved

**Problem**: `VREStateManager` (~385 lines) mixes data scanning/filesystem reactions with UI state (selection, pagination). This makes it hard to reason about, test, or extend independently.

**Proposed fix**: Split into `VREDataService` (filesystem reactions, scanning, resource cache) and a slimmed `VREStateManager` (selection, pagination, page slicing). See Implementation Plans for details.

**Claude correction on Gemini's proposal**: Gemini's 4-way split (`ResourceRepository`, `ClassMetadataScanner`, `SelectionModel`, `PaginationState`) over-fragments tightly coupled state. A 2-way split along the data/UI boundary is cleaner and avoids excessive cross-wiring.

---

### 54. New column doesn't display default value for pre-existing resources

**Creator**: Fernando (manual testing)
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd`, `ui/resource_list/resource_field_label.gd`
**Solved**: not solved

**Problem**: When adding a new `@export` property with a default value (e.g. `@export var my_int: int = 2`) to a class that already has saved `.tres` instances, the new column appears in the table but the cell is blank for pre-existing resources. The Inspector shows the correct default value. The root cause is that `.tres` files only serialize properties whose values differ from the script default. Since the resource was saved *before* the property existed, the `.tres` file has no entry for it. When `ResourceFieldLabel.set_value()` calls `resource.get(col.name)`, Godot returns the script default correctly — but only if the resource's script is properly loaded. The issue is likely in the `owned` dictionary check in `ResourceRow._build_field_labels()`: it builds `owned` from `resource.get_script().get_script_property_list()`, but if the loaded resource still has a stale cached script (due to `CACHE_MODE_REPLACE` timing), the new property may not appear in `owned`, so the label is skipped.

**Fix**: Investigate whether the `owned` check correctly picks up newly added properties after a class change. May need to force-reload the resource's script, or rebuild `owned` from the column list + class hierarchy rather than from the loaded resource's script instance.

---

## Pending Items

- **Item 52**: Granular resource-change signal — emit which specific resources changed instead of full page rebuild
- **Item 53**: StateManager division — split into focused components following MVVM-like pattern
- **Item 54**: New column doesn't display default value for pre-existing resources

---

## Implementation Plans

### Item 52: Granular resource-change signal

**Problem**: `_rescan_resources_only()` already knows exactly which resources are new, modified, or deleted (via mtime comparison), but it discards that information and emits `data_changed` with the full page slice. This causes a full table rebuild even when only one resource changed. The `BulkEditor.resources_edited` path already does targeted row refresh via `refresh_row()` — the rescan path should do the same.

**Proposed fix**:
1. Add a new signal: `signal resources_modified(changed_paths: Array[String])` on `VREStateManager`.
2. In `_rescan_resources_only()`, collect the paths of new/modified/deleted resources into arrays.
3. For modifications: emit `resources_modified` with the changed paths. `ResourceList` calls `refresh_row()` for each.
4. For additions/deletions (structural changes): emit `data_changed` as today (full page rebuild needed since row count changed).
5. This way, the common case (user edits a resource externally) triggers a targeted row update, not a full rebuild.

**Files**: `core/state_manager.gd`, `ui/resource_list/resource_list.gd`, `ui/visual_resources_editor_window.gd`

---

### Item 53: StateManager MVVM-inspired division

**Problem**: `VREStateManager` currently handles: class metadata scanning, resource scanning/caching, selection state, pagination, filesystem change reactions, orphan detection, and class rename detection. This is too many responsibilities in one class (~385 lines).

**What Gemini proposed (and why it's not quite right)**:
Gemini suggested splitting into `ResourceRepository`, `ClassMetadataScanner`, `SelectionModel`, `PaginationState`. The problem with this split is that it fragments state that is tightly coupled — selection depends on the resource list, pagination depends on resource count, and class changes trigger cascading updates across all of them. Four separate objects with cross-references would add wiring complexity without reducing conceptual load.

**What MVVM would imply**:
In MVVM terms:
- **Model**: The data sources — `ProjectClassScanner` (already exists, static utilities), the filesystem, the resource files on disk.
- **ViewModel**: The state that the UI observes — this is what `VREStateManager` currently is. A ViewModel is *expected* to aggregate model data into a shape the View can consume. The issue isn't that VREStateManager has too many fields — it's that it mixes *data transformation* (scanning, property uniting) with *UI state* (selection, pagination) and *side effects* (filesystem signal handling, orphan re-saving).
- **View**: `ResourceList`, `ClassSelector`, etc. — these are already pure views that receive data and emit user actions.

**Proposed split** (2 components, not 4):

1. **`VREDataService`** (new, extends Node) — owns filesystem reactions and data scanning:
   - Connects to `EditorFileSystem` signals
   - Owns `global_classes_map`, `class_to_path_map`, `_classes_parent_map`
   - Owns `project_resource_classes`, `resources`, `_known_resource_mtimes`
   - Owns `_rescan_resources_only()`, `_handle_classes_updated()`, `_resave_orphaned_resources()`
   - Emits: `project_classes_changed`, `resources_changed`, `class_renamed`
   - This is a pure data layer — no knowledge of selection, pagination, or UI

2. **`VREStateManager`** (slimmed down) — owns UI-facing state:
   - Owns `selected_resources`, `_selected_paths`, `_last_anchor`, `_current_page`
   - Owns `columns` (derived from data service's property lists)
   - `select()`, `next_page()`, `prev_page()`
   - Listens to `VREDataService.resources_changed` → restores selection, emits page data
   - Emits: `data_changed`, `selection_changed`, `pagination_changed`

This keeps the two concerns cleanly separated while avoiding the over-fragmentation of 4+ tiny classes that all need to cross-reference each other.

**Files**: `core/state_manager.gd` (refactor), new `core/data_service.gd`, `core/state_manager.tscn` (add child node), `ui/visual_resources_editor_window.gd` (update wiring)

---

## Claude Opus Code Analysis (2026-03-24)

### Overall Impression

This is a well-structured Godot editor plugin for visually browsing, creating, editing, and deleting `.tres` resource files filtered by class type. The architecture is clean — there's a clear separation between scanning (`ProjectClassScanner`), state management (`VREStateManager`), UI (`ResourceList`, `ResourceRow`, `ClassSelector`), and bulk editing (`BulkEditor`). The signal-based wiring in `connect_components()` is explicit and easy to follow. For its scope, this is solid work.

### Architecture Strengths

1. **Good component boundaries.** `VREStateManager` owns all data state (resources, columns, selection, pagination) and emits signals. The window script wires things together but doesn't hold business logic. The `BulkEditor` is a self-contained editing proxy that hooks into Godot's inspector. Each piece can be reasoned about independently.

2. **Incremental rescan via mtime.** `_rescan_resources_only()` uses modification times to detect new/modified/deleted resources without reloading everything. This is a meaningful optimization for large projects.

3. **Smart class rename detection.** `_detect_class_rename()` checks if the old script path now maps to a different class name — cheap and effective for the common rename case.

4. **Orphan resource re-saving.** When a class is removed, `_resave_orphaned_resources()` saves existing `.tres` files so they don't break. This is a thoughtful touch that shows awareness of real-world editor workflows.

5. **Scene-first UI convention followed well.** Most visual structure lives in `.tscn` files. Dialogs without children are script-only nodes added at runtime — exactly the right call per the project conventions.

### Issues and Concerns

#### Bugs / Correctness

1. **Typo in class name: `ComfirmDeleteDialog`** — should be `ConfirmDeleteDialog`. This is a public `class_name` so it propagates everywhere (the window script already references it with the misspelled name).

2. **`header_row.gd` uses `range()` in for loop (line 18)** — `for i: int in range(columns.size())` violates the project convention. Should be `for i: int in columns.size():`.

3. **`_handle_property_changes()` re-saves ALL loaded resources when properties change** (state_manager.gd:333-334). If you have 500 resources loaded and rename a field, it saves all 500 even if only the schema changed. The resources themselves haven't changed on disk — the schema script did. Godot will serialize them correctly on next load without re-saving. This is expensive I/O for no benefit, and it can trigger cascading `filesystem_changed` signals.

4. **`_scan_resources()` uses `CACHE_MODE_REPLACE` for every resource** (project_class_scanner.gd:149). This is intentional to force reloads, but it evicts every resource from Godot's cache. If other parts of the editor hold references to those resources, they'll get stale objects. Consider `CACHE_MODE_REPLACE` only when the class filter actually changes, not on every refresh.

5. **`BulkEditor._on_inspector_property_edited` listens to ALL inspector edits** (bulk_editor.gd:62-86). It correctly checks `edited_obj == _bulk_proxy`, but if the user edits a *different* resource in the inspector while the VRE window is open, this callback fires unnecessarily on every keystroke. Not a bug, but a waste.

6. **`select_class()` in class_selector.gd doesn't emit `class_selected`** — it only visually selects the dropdown item. If a class rename triggers `current_class_renamed → select_class()`, the dropdown updates visually but the window's `_on_class_selected` never fires. The state manager already handles the rename internally, so this works by coincidence, but it's fragile.

#### Performance

7. **Full table rebuild on every page change.** `_emit_page_data()` emits a slice of resources + columns → `ResourceList.set_data()` → `_build_rows()` which destroys and re-instantiates every row. For 50 rows per page, that's 50 scene instantiations, 50+ label instantiations per row (one per column), plus signal connections/disconnections. Object pooling or just hiding/showing rows would be significantly cheaper.

8. **`scan_folder_for_classed_tres_paths()` opens and reads the first line of every `.tres` file** to extract the class. With hundreds of `.tres` files across the project, this is a lot of disk I/O on every scan. Consider caching the class→path mapping and only re-reading files that changed (similar to the mtime approach already used for resources).

9. **`unite_classes_properties()` uses `properties.has(prop)` which is O(n) array scan per property per class.** With many subclasses and many properties, this becomes O(classes × props²). A Dictionary keyed on property name would be O(1) per lookup.

10. **Linear search in `_rescan_resources_only()` for both modified and deleted resources.** `current_paths.has(path)` is O(n) on an Array. For deleted detection, `known_paths` iterates all known paths and does a `.has()` on current_paths for each. Converting `current_paths` to a Dictionary (or set) before the loop would reduce this from O(n²) to O(n).

#### Design / Maintainability

11. **`VisualResourcesEditorWindow` manually copies state between components** in `_on_class_selected()` (lines 56-63). When a class is selected, it sets `BulkEditor.current_class_name`, `current_class_script`, `current_class_property_list`, and `subclasses_property_lists` individually. This is a coupling surface — if `VREStateManager` adds a new field, someone has to remember to forward it. A single state object or having `BulkEditor` observe `VREStateManager` directly would be cleaner.

12. **Debug `print()` statements left in production code.** `state_manager.gd:253` (`print("classes updated")`), `state_manager.gd:383` (`print("fs changed")`), `debounce_timer.gd:19` (`print(callback)`). These will spam the Godot output panel during normal use.

13. **`create_and_add_dialogs()` / `connect_components()` split is awkward.** The toolbar calls both in sequence after instantiation. The comment explains why (Window-in-Window tool mode issues), but the two-step initialization means the window is in a partially-initialized state between calls. A single `initialize()` method that does both would be safer.

14. **`DebounceTimer` has a subtle bug with variadic args.** `start_debouncing(_callback, ..._args)` captures args, and on timeout calls `callback.call(args)` — but `args` is always an Array. If someone called `start_debouncing(my_func, "a", "b")`, the callback receives a single Array `["a", "b"]` instead of two separate arguments. In current usage this doesn't matter (callbacks are zero-arg), but the API is misleading. Also `_on_timout` is misspelled (should be `_on_timeout`).

15. **No keyboard navigation.** The resource list is click-only. Tab/arrow-key navigation through rows would improve editor usability, especially for power users who work keyboard-first. This is a UX gap, not a bug.

16. **`save_resource_dialog` duplicates class-to-path lookup** instead of reusing `class_to_path_map` from `VREStateManager`. It receives `global_classes_map` and iterates it with `_get_class_script_path()`. Passing the already-built `class_to_path_map` would be simpler.

17. **`ResourceRow._build_field_labels()` duplicates the property filtering logic** from `ProjectClassScanner.get_properties_from_script_path()` — the same `usage & PROPERTY_USAGE_EDITOR`, `begins_with("resource_")` checks appear in both places. If the filter criteria change, both need updating. The row could just receive the list of property names its resource owns, rather than re-deriving it.

### Minor Nits

- `plugin.cfg` description: "An visual" → "A visual".
- `header_row.gd` has no `class_name` — intentional (it's a scene-only script), but inconsistent with `ResourceRow` which does have one.
- `_on_close_requested` in the window is connected via the `.tscn` signal connection, but `_unhandled_input` for ESC calls `close_requested.emit()` which triggers it — clean, but the ESC handler doesn't call `get_viewport().set_input_as_handled()`, so the event might propagate.

