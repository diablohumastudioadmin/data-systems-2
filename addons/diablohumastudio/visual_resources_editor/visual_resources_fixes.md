# Visual Resources Editor — Unified Fix List

All items from the three reviews (Claude, Gemini, Codex) merged. Duplicates unified. Conflicts and corrections noted.

---

## Items

### 1. `get_class_from_tres_file()` loads entire resource — performance

**Creator**: Gemini + Codex (Claude noted only the silent failure aspect)
**Severity**: CRITICAL
**File**: `core/project_class_scanner.gd`

**Problem**: Uses `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` for every `.tres` file during scans. Loads full resources with all dependencies (textures, audio, etc.) just to read the script class name. Freezes editor on medium+ projects.

**Fix (Gemini)**: Read `.tres` as plain text with `FileAccess`, parse header with RegEx to find `script_class` or `ExtResource` script reference.
**Fix (Codex)**: Parse `.tres` text for `script = ExtResource` and map to class without fully loading; or cache results and only load on demand.

**problem_claude_correction**: Problem is real and severe. Both Gemini and Codex correctly identified it.
**fix_claude_correction**: Both fixes are directionally correct. Prefer Codex's approach: parse the `.tres` header text for the `[ext_resource ... type="Script"]` and `script = ExtResource(...)` lines, then map the script path to a class name via the already-cached `_global_classes_map`. This avoids RegEx fragility while still avoiding full loads. Must handle binary `.tres` files gracefully (skip them or fall back to load).

---

### 2. Silent failure when load returns null

**Creator**: Claude
**Severity**: HIGH
**File**: `core/project_class_scanner.gd` — `get_class_from_tres_file()` lines 89-94

**Problem**: When `ResourceLoader.load()` returns null (corrupt file, missing script), the function silently returns `""`. Resource vanishes from list with no warning.

**Fix**: Add `push_warning("VRE: Failed to load resource at '%s'" % tres_file_path)` before returning empty.

---

### 3. Invalid/fragile Array syntax

**Creator**: Gemini + Claude
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — `get_descendant_classes()`

**Problem (Gemini)**: `Array([], TYPE_STRING, "", null)` is "invalid Godot 4 syntax".
**Problem (Claude)**: Same line — fragile and hard to read.

**problem_claude_correction**: Gemini is wrong that it's "invalid syntax" — `Array([], TYPE_STRING, "", null)` IS valid Godot 4 typed array constructor. It compiles and runs. But it IS fragile and unreadable.
**Fix**: Replace with simple `var descendants: Array[String] = []` then conditionally `append(base_class)`.

---

### 4. O(N^2) map building — uncached `get_global_class_list()`

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `core/project_class_scanner.gd`

**Problem**: Multiple functions iterate over `ProjectSettings.get_global_class_list()` independently instead of sharing a single cached result.

**Fix**: Call `get_global_class_list()` once per filesystem change, cache the parsed maps. StateManager already calls `_set_maps()` in `rescan()`, so ensure all downstream code uses the cached maps, not fresh API calls.

**Conflicting**: Item #22 (BulkEditor also calls `get_global_class_list()` independently).

---

### 5. Reference type mutation in bulk proxy

**Creator**: Gemini
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_create_bulk_proxy()` line 35

**Problem**: `_bulk_proxy.set(prop.name, edited_resources[0].get(prop.name))` copies references for Array/Dictionary types. Editing an Array in the bulk proxy mutates the first resource's Array directly, bypassing save logic.

**Fix**: Deep-duplicate reference types:
```gdscript
var value: Variant = edited_resources[0].get(prop.name)
if value is Array or value is Dictionary:
    value = value.duplicate(true)
_bulk_proxy.set(prop.name, value)
```

---

### 6. Cached EditorInspector reference goes stale

**Creator**: Claude
**Severity**: CRITICAL
**File**: `core/bulk_editor.gd` — line 13

**Problem**: `var _inspector: EditorInspector = EditorInterface.get_inspector()` cached at member level. If editor layout changes, reference becomes stale, signal connections silently stop.

**Fix**: Fetch fresh inspector in `_ready()` and re-fetch when needed. Don't cache at declaration time.

---

### 7. Missing bulk proxy cleanup / inspector not cleared on empty selection

**Creator**: Claude + Codex
**Severity**: CRITICAL
**File**: `core/bulk_editor.gd`

**Problem (Claude)**: `_bulk_proxy` is never freed. Old proxies accumulate in memory.
**Problem (Codex)**: When user deselects all rows, inspector still shows stale proxy.

**Fix**: Add `_clear_bulk_proxy()` that sets `_bulk_proxy = null` and calls `EditorInterface.inspect_object(null)`. Call it at start of `_create_bulk_proxy()` and when `edited_resources` becomes empty.

---

### 8. BulkEditor applies properties to resources that don't have them

**Creator**: Codex
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_on_inspector_property_edited()` line 53

**Problem**: `res.set(property, new_value)` is called blindly on all selected resources. In subclass mode, a property from `Sword` gets set on a `Bow` resource, polluting it with unintended values.

**Fix**: Check property exists before setting:
```gdscript
var res_props: Array = res.get_property_list()
var has_prop: bool = false
for p: Dictionary in res_props:
    if p.name == property:
        has_prop = true
        break
if has_prop:
    res.set(property, new_value)
```

**fix_claude_correction**: The fix works but is O(N*M). Better: build a `Dictionary` of property names once per resource script and check with `.has()`. Or even simpler — cache the owned properties set per class_name since it doesn't change between edits.

---

### 9. Partial save emits full success

**Creator**: Claude
**Severity**: HIGH
**File**: `core/bulk_editor.gd` — `_on_inspector_property_edited()` lines 51-59

**Problem**: If `ResourceSaver.save()` fails for some resources, `resources_edited` signal is emitted with ALL resources (including failed ones). UI refreshes as if everything succeeded.

**Fix**: Only emit successfully saved resources in the signal.

---

### 10. O(N) script lookup in BulkEditor

**Creator**: Gemini
**Severity**: LOW
**File**: `core/bulk_editor.gd` — `_get_current_class_script()` lines 39-43

**Problem**: Iterates `get_global_class_list()` every time a property is edited to find the current class script.

**Fix**: Cache the script reference when `current_class_name` is set.

**Conflicting**: Item #4 (same root cause — uncached class list).

---

### 11. Naive error handling — UI overflow

**Creator**: Gemini
**Severity**: LOW
**File**: `core/bulk_editor.gd` — line 58

**Problem**: If 50 resources fail to save, the error string overflows the popup.

**Fix**: Limit error output to first 5-10 paths and append "... and X more".

---

### 12. Bulk edit saves on every property edit, no undo/redo

**Creator**: Codex
**Severity**: HIGH
**File**: `core/bulk_editor.gd`

**Problem**: Every single property edit triggers immediate save of all selected resources with no UndoRedo support. Destructive UX.

**Fix (Codex)**: Use `EditorUndoRedoManager` to register changes. Debounce/batch saves.

**problem_claude_correction**: Problem is real. However, CLAUDE.md explicitly states: "Bulk edit undo/redo is optional; do not block work on adding it unless explicitly requested." This is a known accepted trade-off, not a forgotten bug. Debouncing saves IS worth doing though.

---

### 13. Premature initialization in StateManager

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `core/state_manager.gd` — line 15

**Problem**: `var project_resource_classes: Array[String] = ProjectClassScanner.get_resource_classes_in_folder()` executes heavy I/O at object instantiation (during `_init`), before `_ready()`.

**Fix**: Initialize as empty array, populate in `_ready()`.

---

### 14. Typo: double space in timer disconnect

**Creator**: Gemini
**Severity**: LOW
**File**: `core/state_manager.gd` — line 39

**Problem**: `if  %RescanDebounceTimer` has double space.

**Fix**: Remove extra space.

**problem_claude_correction**: The double space is cosmetic and doesn't affect behavior. Valid but trivial.

---

### 15. Unnecessary getters without return types

**Creator**: Gemini
**Severity**: LOW
**File**: `core/state_manager.gd` — lines 70-77

**Problem**: `get_class_names()`, `get_columns()`, `get_resources()` have no return types and just return public vars.

**Fix**: Either add return types or remove the getters entirely (vars are already public).

**problem_claude_correction**: Partially valid. The vars `columns` and `resources` are public, so getters are redundant. But `_current_class_names` is private, so `get_class_names()` provides access — that getter is useful. Fix should be: add return types to all, keep `get_class_names()`, consider removing the others.

---

### 16. Missing empty-class validation in rescan

**Creator**: Claude
**Severity**: HIGH
**File**: `core/state_manager.gd` — `rescan()` lines 60-62

**Problem**: If `_get_included_classes()` returns empty (deleted class, corrupt parent map), columns and resources are silently empty. UI shows "0 resources" with no explanation.

**Fix**: Check and `push_warning()` when class name is set but resolution returns empty.

---

### 17. Full project re-scan on any filesystem change (no incremental updates)

**Creator**: Codex
**Severity**: CRITICAL
**File**: `core/state_manager.gd`, `core/project_class_scanner.gd`

**Problem**: Every `filesystem_changed` triggers debounce then full recursive scan + load of all `.tres` files. Falls over on medium/large projects.

**Fix**: Build a cached index `path -> class_name`, update incrementally on changes. Use `EditorFileSystem` APIs to detect which files changed. Only reload changed files.

**problem_claude_correction**: Problem is real and will become severe at scale. However, the current debounce timer already mitigates rapid-fire rescans. The fix is architecturally correct but is a significant refactor — should be planned as a dedicated phase, not a quick fix.

---

### 18. Class list change detection is order-sensitive

**Creator**: Codex
**Severity**: MEDIUM
**File**: `core/state_manager.gd` — `_check_project_classes_changed()` line 88

**Problem**: `new_classes == project_resource_classes` compares arrays directly. If order changes but set is identical, it triggers unnecessary UI refresh.

**Fix**: Sort both arrays before comparing, or compare as sets.

**problem_claude_correction**: Looking at the code, `get_resource_classes_in_folder()` returns classes from `get_global_class_list()` which has a stable order. And `set_classes_in_dropdown()` sorts alphabetically anyway. So the order instability is unlikely in practice. Low-risk fix but not urgent.

---

### 19. EditorFileSystemDirectory traversal during rescan

**Creator**: Claude
**Severity**: CRITICAL
**File**: `core/state_manager.gd` — `rescan()` line 64

**Problem**: `get_filesystem()` returns a reference Godot frees on every `scan()`. If rescan triggers mid-traversal, reference becomes freed → crash.

**Fix**: Guard with `is_instance_valid(root)` checks during traversal.

---

### 20. Dictionary `.has()` doesn't deduplicate by content

**Creator**: Claude
**Severity**: HIGH
**File**: `core/project_class_scanner.gd` — `unite_classes_properties()`

**Problem**: `properties.has(prop)` compares Dictionary references, not content. Duplicate columns accumulate.

**Fix**: Track by property name in a separate `Dictionary[String, bool]` and check `.has(prop.name)`.

---

### 21. Property usage filter mismatch between scanner and row

**Creator**: Codex
**Severity**: HIGH
**File**: `core/project_class_scanner.gd`, `ui/resource_list/resource_row.gd`

**Problem**: `unite_classes_properties()` filters properties by `PROPERTY_USAGE_EDITOR`, but `ResourceRow._build_field_labels()` uses `get_script_property_list()` to build `owned` dict WITHOUT the same filter. A property excluded from columns could still appear as "owned", or vice versa.

**Fix**: Apply the same `PROPERTY_USAGE_EDITOR` filter in `_build_field_labels()` when building the `owned` dictionary.

---

### 22. O(N) lookup in SaveResourceDialog

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/dialogs/save_resource_dialog.gd`

**Problem**: `_get_class_script_path()` does its own full pass over `ProjectSettings.get_global_class_list()` instead of using the centralized cache.

**Fix**: Accept the script path as a parameter or use the cached maps from StateManager/ProjectClassScanner.

**Conflicting**: Item #4, #10 (same root cause).

---

### 23. SaveResourceDialog doesn't debounce scan

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/dialogs/save_resource_dialog.gd` — line 40

**Problem**: Calls `EditorInterface.get_resource_filesystem().scan()` directly. Multiple rapid saves trigger independent scans, uncoordinated with StateManager's debounce timer.

**Fix**: Remove `scan()` call. Let `filesystem_changed` propagate naturally through StateManager's debounce.

---

### 24. No overwrite warning on save

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/dialogs/save_resource_dialog.gd`

**Problem**: Saving a new resource can overwrite an existing file with no warning.

**Fix**: Check `FileAccess.file_exists(target_path)` and show confirmation dialog before overwriting.

---

### 25. Signal connection leak in ResourceList

**Creator**: Claude
**Severity**: CRITICAL
**File**: `ui/resource_list/resource_list.gd` — `_clear_rows()` lines 57-62

**Problem**: Rows freed via `queue_free()` but signal connections (`resource_row_selected`, `delete_requested`) never disconnected. Signal could fire between `queue_free()` and actual deletion.

**Fix**: Disconnect signals before freeing each row.

---

### 26. Null pointer crash in ResourceList selection

**Creator**: Claude
**Severity**: CRITICAL
**File**: `ui/resource_list/resource_list.gd` — lines 71, 74, 81

**Problem**: `_resource_to_row[resource].set_selected()` called without checking key exists or row is valid. Crashes if resource deleted while selected.

**Fix**: Guard with `_resource_to_row.has(resource) and is_instance_valid(...)`.

---

### 27. Shift-click is toggle, not range select

**Creator**: Gemini + Codex
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`, `ui/resource_list/resource_row.gd`

**Problem (both)**: Shift toggles individual items. Standard UX: Shift = range select, Ctrl/Cmd = toggle.

**Fix**: Track `_last_selected_index`. Shift+click selects all rows between last and current. Use Ctrl/Cmd for toggle.

---

### 28. Shift detection via `Input.is_key_pressed(KEY_SHIFT)` is unreliable

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 119

**Problem**: Checks global keyboard state at signal fire time. If Shift released slightly before mouse button, detection fails.

**Fix**: Override `_gui_input(event)` and check `event.shift_pressed` on `InputEventMouseButton`.

**problem_claude_correction**: The timing issue is theoretical — `Input.is_key_pressed()` polls at signal emission time, which is the same frame as the click. In practice this works fine in editor tools. However, `_gui_input` with `event.shift_pressed` IS the proper Godot pattern and also enables Ctrl detection for item #27. So the fix is good, just the problem severity is overstated.

---

### 29. Stale resource references after rescan

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`

**Problem**: `selected_rows` stores `Resource` instances. After rescan, resources may be reloaded as new objects, breaking selection state.

**Fix**: Track selection by `resource_path` (String), resolve to current row after refresh.

---

### 30. Layout jitter from dynamic button text

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/resource_list/resource_list.gd` — line 89

**Problem**: `"Delete Selected (%d)"` changes string length, causing horizontal layout shift on every selection change.

**Fix**: Set `custom_minimum_size.x` on the button, or use a separate fixed-width label for the count.

---

### 31. No virtualization in resource list

**Creator**: Codex (Claude noted as "full table rebuild")
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_list.gd`, `ui/resource_list/resource_row.gd`

**Problem**: Full control row instantiated for every resource. UI freezes on large lists.

**Fix (Codex)**: Replace with `Tree` or implement row pooling/virtualization.

**problem_claude_correction**: Valid at scale. However, for the typical use case (< 100 resources of a given class), the current approach works fine. A `Tree` would also require rewriting all row rendering logic. Recommend: first implement incremental updates (skip rebuild when data unchanged), defer full virtualization until proven needed.

---

### 32. StyleBox memory bloat in ResourceRow

**Creator**: Gemini
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 91

**Problem**: `_color_style.duplicate()` called for every color cell in every row. Thousands of orphaned StyleBox resources over time.

**Fix (Gemini)**: Use a `ColorRect` instead of hacking Label's StyleBox, or reuse StyleBoxes.

**problem_claude_correction**: The problem is real. However, StyleBoxes are reference-counted Resources in Godot — when the Label is freed, its overrides are freed too. So "orphaned" is overstated. The real issue is unnecessary allocation pressure during row building. Fix is valid: a `ColorRect` behind the label is cleaner, or cache StyleBoxes per unique color.

---

### 33. Missing bounds/null checks on column access

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/resource_list/resource_row.gd` — line 51

**Problem**: `columns[i].name` accessed without null check. Malformed column Dictionary crashes.

**Fix**: Validate `col.has("name")` before accessing.

---

### 34. ResourceRow assumes toggle_mode configured in scene

**Creator**: Codex
**Severity**: LOW
**File**: `ui/resource_list/resource_row.gd`

**Problem**: `button_pressed` only works if `toggle_mode = true`. If scene changes, selection breaks silently.

**Fix**: Set `toggle_mode = true` defensively in `_ready()`.

**problem_claude_correction**: Valid defensive coding. However, `toggle_mode` IS set in the `.tscn` scene file. Setting it again in `_ready()` is harmless but redundant. Low priority.

---

### 35. Duplicate dropdown-building code in ClassSelector

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/class_selector/class_selector.gd` — `set_classes_in_dropdown()` and `_rebuild_dropdown_preserving_selection()`

**Problem**: Nearly identical dropdown rebuild logic in two methods.

**Fix**: Extract to shared `_populate_dropdown(preserve_selection: bool)`.

---

### 36. Redundant setter + method in ClassSelector

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/class_selector/class_selector.gd` — setter on line 7 + `set_classes()` on line 27

**Problem**: Both the `_classes_names` setter and `set_classes()` do the same thing.

**Fix**: Remove one. Keep `set_classes()` as the public API and remove the setter, or keep the setter and remove `set_classes()`.

**problem_claude_correction**: Looking at the code, the setter (line 6-10) triggers `set_classes_in_dropdown()` when `is_node_ready()`. `set_classes()` (line 27-30) does the same thing. They ARE redundant. However, the setter fires on ANY assignment (`_classes_names = x`), while `set_classes()` is an explicit method. Having both is confusing but not harmful. Recommend: keep `set_classes()` as public API, make setter call it internally to avoid duplication.

**Conflicting**: Item #35 (both address ClassSelector duplication).

---

### 37. Inefficient array iteration

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/class_selector/class_selector.gd`

**Problem**: `for i: int in range(_classes_names.size())` instead of `for i: int in _classes_names.size()`.

**problem_claude_correction**: This is a non-issue. Both forms are equivalent in GDScript 4. `range()` is NOT slower — GDScript optimizes it identically. The `in size` form is marginally more concise but not measurably faster. Remove from fix list.

---

### 38. Class selector resets silently when selected class disappears

**Creator**: Codex
**Severity**: MEDIUM
**File**: `ui/class_selector/class_selector.gd`

**Problem**: If the selected class is removed from the project, dropdown falls back to placeholder silently. No warning to user.

**Fix**: Emit a signal or show a warning when the selected class disappears.

---

### 39. Initialization order risk in Window

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/visual_resources_editor_window.gd` — `_ready()` lines 5-22

**Problem**: `%ClassSelector.set_classes()` called before connecting to `%VREStateManager.data_changed`. If `set_classes()` triggers internal class selection, state won't sync.

**Fix**: Connect signals first, then set initial state.

---

### 40. Global `_input` for ESC key in Window

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/visual_resources_editor_window.gd` — line 25-26

**Problem**: `_input()` catches `ui_cancel` globally when window is focused, potentially intercepting other editor popups.

**Fix**: Use `_unhandled_input()` instead, or remove entirely (Window already emits `close_requested` on ESC if not exclusive).

---

### 41. Missing path validation before delete

**Creator**: Claude
**Severity**: MEDIUM
**File**: `ui/dialogs/confirm_delete_dialog.gd`

**Problem**: `DirAccess.remove_absolute()` doesn't validate path is within project. Malformed path could delete arbitrary files.

**Fix**: Check `path.begins_with("res://")` before deleting.

---

### 42. Deleting resources is irreversible, bypasses undo

**Creator**: Codex
**Severity**: HIGH
**File**: `ui/dialogs/confirm_delete_dialog.gd`

**Problem**: Deletion cannot be undone. Unacceptable for editor tooling.

**Fix (Codex)**: Use UndoRedo APIs or implement a recycle bin.

**problem_claude_correction**: CLAUDE.md explicitly states: "Deleting resource files does not require undo/redo; use version control for recovery." This is a deliberate design decision, not a forgotten feature. A "move to trash" approach could be nice-to-have but is not required.

---

### 43. Orphaned `.uid` files after delete

**Creator**: Gemini
**Severity**: LOW
**File**: `ui/dialogs/confirm_delete_dialog.gd`

**Problem**: Deleting `.tres` files leaves behind `.uid` metadata files.

**problem_claude_correction**: This is WRONG. Per CLAUDE.md: ".tres and .tscn files do NOT create .uid sidecars — their UID is embedded in the file header." Only `.gd` scripts generate `.uid` sidecar files. Deleting a `.tres` does NOT leave orphaned `.uid` files. Remove from fix list.

---

### 44. Plugin typo "shubmenu"

**Creator**: Gemini
**Severity**: LOW
**File**: `visual_resources_editor_plugin.gd` — line 11

**Problem**: `MainToolbarPlugin.add_toolbar_shubmenu(...)`. Typo confirmed in code. Interestingly, line 14 uses the correct `remove_toolbar_submenu`.

**Fix**: Rename to `add_toolbar_submenu` (requires fixing `MainToolbarPlugin` too).

---

### 45. Untyped Dictionary parameters

**Creator**: Claude
**Severity**: LOW
**File**: `core/project_class_scanner.gd` — multiple functions

**Problem**: `classes_parent_map: Dictionary` should be `Dictionary[String, String]` for type safety.

**Fix**: Add explicit typed Dictionary signatures.

**problem_claude_correction**: Looking at the actual code, `_classes_parent_map` on line 9 of `state_manager.gd` IS already typed as `Dictionary[String, String]`. The scanner function `get_resource_classes_in_folder` also uses `Dictionary[String,String]`. Some other functions may still lack typing — verify each.

---

### 46. Typo: `_global_clases_map`

**Creator**: Claude + Codex
**Severity**: LOW
**File**: `core/state_manager.gd` — line 8

**Problem**: `clases` (Spanish) instead of `classes`.

**Fix**: Rename to `_global_classes_map` everywhere.

---

### 47. Signal connections hidden in scenes

**Creator**: Codex
**Severity**: LOW

**Problem**: Important signal wiring split between code and `.tscn` files.

**problem_claude_correction**: This is NOT a problem. Per CLAUDE.md convention, signal connections in `.tscn` scenes are standard Godot practice. The convention explicitly says to wire signals in the scene where appropriate. Remove from fix list.

---

### 48. No tests for scanning or CRUD

**Creator**: Codex
**Severity**: MEDIUM

**Problem**: Entire plugin is untested.

**Fix**: Add editor tests for scan logic and CRUD paths.

---

### 49. Hard-coded strings and magic numbers

**Creator**: Codex
**Severity**: LOW

**Problem**: Labels and sizes are hard-coded.

**Fix**: Move to constants or localization table.

**problem_claude_correction**: For an internal editor tool, hard-coded strings are acceptable. Localization tables are overkill unless the plugin will be distributed. Magic numbers (if any) should be constants, but this is low priority.

---

---

## Summary Table

Items marked for removal have `problem_claude_correction` explaining why. Use checkboxes to tell me what to do.

| # | Creator | Title | Fix (short) | Conflicted | Problem corrected | Fix corrected | For later | Implement | Remove | Comment |
|---|---------|-------|-------------|------------|-------------------|---------------|-----------|-----------|--------|---------|
| 1 | Gemini+Codex | tres file full-load perf | Parse header text instead of ResourceLoader.load | — | — | Prefer text parse + class map lookup, handle binary tres | [ ] | [ ] | [ ] | |
| 2 | Claude | Silent failure on null load | Add push_warning before returning empty | — | — | — | [ ] | [ ] | [ ] | |
| 3 | Gemini+Claude | Fragile Array syntax | Use `Array[String] = []` + conditional append | — | Gemini wrong: syntax IS valid, just fragile | — | [ ] | [ ] | [ ] | |
| 4 | Gemini | Uncached get_global_class_list | Call once per fs change, cache maps | #10, #22 | — | — | [ ] | [ ] | [ ] | |
| 5 | Gemini | Bulk proxy ref-type mutation | `.duplicate(true)` for Array/Dict before set | — | — | — | [ ] | [ ] | [ ] | |
| 6 | Claude | Stale EditorInspector cache | Fetch fresh inspector, don't cache at declaration | — | — | — | [ ] | [ ] | [ ] | |
| 7 | Claude+Codex | Bulk proxy not cleaned up / stale inspector | Add _clear_bulk_proxy(), call on empty selection | — | — | — | [ ] | [ ] | [ ] | |
| 8 | Codex | Bulk edit sets props on wrong subclass | Check property exists before set | — | — | Build prop name set per class, O(1) lookup | [ ] | [ ] | [ ] | |
| 9 | Claude | Partial save emits full success | Only emit successfully saved resources | — | — | — | [ ] | [ ] | [ ] | |
| 10 | Gemini | O(N) script lookup in BulkEditor | Cache script ref when class_name set | #4, #22 | — | — | [ ] | [ ] | [ ] | |
| 11 | Gemini | Error output overflows UI | Limit to 5-10 paths + "and X more" | — | — | — | [ ] | [ ] | [ ] | |
| 12 | Codex | Bulk edit no undo/redo | Use EditorUndoRedoManager | — | CLAUDE.md says optional, not forgotten | Debounce saves yes; full undo/redo optional | [ ] | [ ] | [ ] | |
| 13 | Gemini | Premature init in StateManager | Init empty, populate in _ready() | — | — | — | [ ] | [ ] | [ ] | |
| 14 | Gemini | Double space typo in timer disconnect | Remove extra space | — | Cosmetic only, no behavior impact | — | [ ] | [ ] | [ ] | |
| 15 | Gemini | Unnecessary getters no return types | Add return types or remove redundant ones | — | get_class_names() IS useful (private var) | Keep get_class_names(), remove others or add types | [ ] | [ ] | [ ] | |
| 16 | Claude | Empty class list no warning | push_warning when class set but resolution empty | — | — | — | [ ] | [ ] | [ ] | |
| 17 | Codex | Full rescan on any fs change | Cached index + incremental updates | — | — | Real but big refactor; plan as phase, not quick fix | [ ] | [ ] | [ ] | |
| 18 | Codex | Order-sensitive class list compare | Sort before compare or use sets | — | Unlikely in practice, stable order from API | — | [ ] | [ ] | [ ] | |
| 19 | Claude | EditorFileSystemDir freed mid-traversal | Guard with is_instance_valid() | — | — | — | [ ] | [ ] | [ ] | |
| 20 | Claude | Dict .has() ref equality, not content | Track by prop name in separate Dict | — | — | — | [ ] | [ ] | [ ] | |
| 21 | Codex | Property usage filter mismatch | Apply same PROPERTY_USAGE_EDITOR filter in row | — | — | — | [ ] | [ ] | [ ] | |
| 22 | Gemini | SaveDialog independent class list lookup | Use centralized cache | #4, #10 | — | — | [ ] | [ ] | [ ] | |
| 23 | Claude | SaveDialog doesn't debounce scan | Remove scan() call, let fs_changed propagate | — | — | — | [ ] | [ ] | [ ] | |
| 24 | Codex | No overwrite warning on save | Check file_exists, show confirmation | — | — | — | [ ] | [ ] | [ ] | |
| 25 | Claude | Signal connection leak in ResourceList | Disconnect signals before queue_free | — | — | — | [ ] | [ ] | [ ] | |
| 26 | Claude | Null pointer crash in selection | Guard _resource_to_row access | — | — | — | [ ] | [ ] | [ ] | |
| 27 | Gemini+Codex | Shift = toggle, not range select | Track last_selected_index, Shift=range, Ctrl=toggle | — | — | — | [ ] | [ ] | [ ] | |
| 28 | Gemini | Input.is_key_pressed unreliable | Use _gui_input + event.shift_pressed | — | Theoretical; works fine in practice | Fix still good (enables Ctrl detection for #27) | [ ] | [ ] | [ ] | |
| 29 | Codex | Stale resource refs after rescan | Track selection by resource_path | — | — | — | [ ] | [ ] | [ ] | |
| 30 | Gemini | Layout jitter from button text | Fixed min_size or separate count label | — | — | — | [ ] | [ ] | [ ] | |
| 31 | Codex+Claude | No row virtualization / full rebuild | Tree or row pooling; incremental update first | — | — | Incremental update first, defer virtualization | [ ] | [ ] | [ ] | |
| 32 | Gemini | StyleBox memory bloat in rows | Use ColorRect or cache StyleBoxes per color | — | StyleBoxes ARE ref-counted, freed with Label | Allocation pressure is real; ColorRect is cleaner | [ ] | [ ] | [ ] | |
| 33 | Claude | Missing bounds check on column access | Validate col.has("name") | — | — | — | [ ] | [ ] | [ ] | |
| 34 | Codex | toggle_mode assumed from scene | Set toggle_mode = true in _ready() | — | Already set in .tscn, redundant but harmless | — | [ ] | [ ] | [ ] | |
| 35 | Claude | Duplicate dropdown code | Extract _populate_dropdown(preserve) | #36 | — | — | [ ] | [ ] | [ ] | |
| 36 | Gemini | Redundant setter + set_classes() | Remove one, keep public API | #35 | Both exist but aren't harmful | Keep set_classes(), simplify setter | [ ] | [ ] | [ ] | |
| 37 | Gemini | Inefficient range() iteration | Use `in size` instead of `in range(size)` | — | NON-ISSUE: both identical in GDScript | — | [ ] | [ ] | [x] | |
| 38 | Codex | Class selector silent reset | Emit signal or show warning | — | — | — | [ ] | [ ] | [ ] | |
| 39 | Claude | Init order risk in Window | Connect signals before setting state | — | — | — | [ ] | [ ] | [ ] | |
| 40 | Gemini | Global _input for ESC | Use _unhandled_input or remove | — | — | — | [ ] | [ ] | [ ] | |
| 41 | Claude | No path validation before delete | Check path.begins_with("res://") | — | — | — | [ ] | [ ] | [ ] | |
| 42 | Codex | Delete is irreversible, no undo | UndoRedo or recycle bin | — | CLAUDE.md: undo for delete not required | Nice-to-have, not required | [ ] | [ ] | [ ] | |
| 43 | Gemini | Orphaned .uid after tres delete | Delete .uid sidecar too | — | WRONG: .tres has NO .uid sidecar | — | [ ] | [ ] | [x] | |
| 44 | Gemini | Plugin typo "shubmenu" | Rename to add_toolbar_submenu | — | — | — | [ ] | [ ] | [ ] | |
| 45 | Claude | Untyped Dictionary params | Add Dictionary[String, String] types | — | Some already typed, verify each | — | [ ] | [ ] | [ ] | |
| 46 | Claude+Codex | Typo _global_clases_map | Rename to _global_classes_map | — | — | — | [ ] | [ ] | [ ] | |
| 47 | Codex | Signal connections in scenes | Document or move to code | — | NOT a problem per CLAUDE.md convention | — | [ ] | [ ] | [x] | |
| 48 | Codex | No tests | Add editor tests for scan + CRUD | — | — | — | [ ] | [ ] | [ ] | |
| 49 | Codex | Hard-coded strings | Move to constants or localization | — | Acceptable for internal editor tool | Overkill unless distributing plugin | [ ] | [ ] | [ ] | |
