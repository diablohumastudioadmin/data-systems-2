# VRE New Architecture — Fixes & Open Issues

Consolidated list from Claude, Codex, and Gemini analyses. Items that appear in multiple analyses are merged.

---

## Items

---

### 1. God-Object `VREStateManager` (internal split)

**Proposed by:** Claude, Codex, Gemini
**Status:** ✅ Solved

**Problem:** `VREStateManager` handled class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic, filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and 12 signals — at least 6 distinct responsibilities in one file.

**Fix:** Split into focused `RefCounted` sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`). `VREStateManager` is now a thin coordinator (~170 LOC) that wires them together and exposes the same public API to UI.

---

### 2. Scattered Resource Saving + Filesystem Bounce Loop

**Proposed by:** Claude (Critical No.2), Codex (No.5 / Phase 2)
**Status:** ❌ Not solved

**Problem (Claude):** `VREStateManager` calls `ResourceSaver.save()` directly in `_resave_orphaned_resources()` and `_handle_property_changes()`. `BulkEditor` also has its own `ResourceSaver.save()` loop. If saving behavior ever needs to change, every site must be hunted down.

**Problem (Codex):** Even after the sub-manager split, `BulkEditor` still calls `ResourceSaver.save()` directly. Every such save triggers `EditorFileSystem.filesystem_changed`, which causes `_refresh_current_class_resources()`, `_selection.restore()`, and the inspector proxy rebuild. The inspector loses focus because the UI refresh happens while the user is typing.

**Fix (Codex):** Add `save_resources()` to `ResourceRepository` that encapsulates the save call, updates `_mtimes`, and returns saved paths. Have `BulkEditor` call the repository helper instead of invoking `ResourceSaver` directly. Introduce a `FilesystemRefreshManager` that `BulkEditor` notifies of internal saves (`notify_internal_save(paths)`), so the next `filesystem_changed` event can be ignored or merged.

```gdscript
func save_resources(resources: Array[Resource]) -> Array[String]:
    var saved_paths: Array[String] = []
    for res: Resource in resources:
        var err: Error = ResourceSaver.save(res, res.resource_path)
        if err == OK:
            _mtimes[res.resource_path] = FileAccess.get_modified_time(res.resource_path)
            saved_paths.append(res.resource_path)
    return saved_paths
```

**Claude counter-proposal:** The `FilesystemRefreshManager` is over-engineering — we already have `EditorFileSystemListener`. The simpler fix: add `acknowledge_saves(resources: Array[Resource])` to `ResourceRepository` (updates `_mtimes` for saved paths) and call it from `VREStateManager.notify_resources_edited()`. `resave_all()` and `resave_resources()` call `_rebuild_mtimes()` after saving. No new class needed. `BulkEditor` keeps calling `ResourceSaver.save()` directly for now — what matters is that `_mtimes` is updated before the next `scan_for_changes()` runs.

---

### 3. `EditorFileSystemListener` Decoupling

**Proposed by:** Claude (Worth No.1)
**Status:** ✅ Solved

**Problem:** Despite having a `core/editor_filesystem_listener.gd`, the old `VREStateManager` still connected directly to `EditorInterface.get_resource_filesystem()` signals in `_ready()`.

**Fix:** All filesystem signal handling now routes through `EditorFileSystemListener`. It emits `filesystem_changed` and `script_classes_updated`. `VREStateManager` subscribes to those, decoupling the data layer from the Godot editor interface.

---

### 4. Narrow State Manager Injection

**Proposed by:** Claude (Worth No.2), Gemini (No.1)
**Status:** ❌ Not solved

**Problem (Claude):** Every UI component receives the full `VREStateManager`. `PaginationBar` only needs `prev_page`, `next_page`, and `pagination_changed`. Passing the whole manager makes the dependency surface larger than necessary and blocks independent testing.

**Problem (Gemini):** This violates the Interface Segregation Principle. Even though `%PaginationBar` only needs page numbers, it is handed the entire `VREStateManager` — meaning it theoretically has access to delete files or scan the filesystem. Testing a simple UI component requires mocking the entire god object.

**Fix (Claude, after the split):** Pass only the sub-manager each component actually needs. `PaginationBar` gets a `PaginationManager`. `ResourceList` gets a `ResourceRepository` and `SelectionManager`. Not worth doing before the internal split (already done).

**Fix (Gemini):** UI components define exactly what they need via smaller managers injected from the window. The Coordinator connects them at the top level.

```gdscript
# ui/visual_resources_editor_window.gd
func _ready() -> void:
    _state = VREStateManager.new()
    _state.start()
    %ResourceList.setup(_state._resource_repo, _state._selection)
    %PaginationBar.setup(_state._pagination)
    %BulkEditor.setup(_state._resource_repo, _state._selection)
    %ClassSelector.setup(_state._class_registry)
```

**Claude note:** The `setup()` approach breaks our CLAUDE.md convention (property setter + `_ready()` guard pattern). Prefer adding typed sub-manager properties (`var resource_repo: ResourceRepository`) following the same setter pattern, instead of a `setup()` method.

---

### 5. Rigid UI Coupling via `%UniqueNames`

**Proposed by:** Codex (No.4), Gemini (No.4)
**Status:** ❌ Not solved (intentional for now)

**Problem:** `visual_resources_editor_window.gd` reaches into the scene tree using `%UniqueName` references. Any rename of those nodes or re-parenting silently breaks the script at runtime with no compile-time warning.

**Fix (Codex):** Expose children as explicit `@export var class_selector: NodePath` and use `get_node()`. Optionally introduce a `WindowController` that children register with.

**Fix (Gemini):** Use `@export var class_selector: Control` to make dependencies clear in the inspector and allow scene tree reorganization without breaking script references.

**Claude counter-proposal:** `%UniqueName` references ARE the project convention per CLAUDE.md ("Use `%UniqueNode` directly in code"). `@export NodePath` adds boilerplate with little gain; the `get_node()` call is fragile in the same way. A `WindowController` with `register_child(self)` is over-engineering for a single-window plugin. The real guard: keep node unique names stable and treat renaming a unique node the same as renaming a public API (requires updating the script too). Not worth changing.

---

### 6. Synchronous Scanning Bottlenecks

**Proposed by:** Codex (No.2), Gemini (No.2)
**Status:** ❌ Not solved

**Problem (Codex):** `ProjectClassScanner` scans `res://` on the main thread, quadratically syncing with `EditorFileSystem.filesystem_changed`. See `core/project_class_scanner.gd` and `core/resource_repository.gd` for the scan/rescan loops.

**Problem (Gemini):** Heavy file I/O managed synchronously via the central state manager will freeze the Godot Editor UI during large project scans, resulting in a poor and unresponsive user experience.

**Fix (Gemini):** Run the scanner asynchronously in a separate `Thread`. Use signals to report progress and completion. The state coordinator acts as an async bridge, updating the UI safely when background tasks emit results.

**Claude note:** GDScript threads are limited and introduce complexity. The EditorFileSystem already handles the heavy scanning; our `ProjectClassScanner` calls only read first lines of `.tres` files and first-line-only `.gd` parsing — relatively fast for typical project sizes. Worth profiling before investing in threading. Start with async only if scanning is measurably slow on real projects (100+ resources).

---

### 7. Manual Window Lifecycle Management

**Proposed by:** Codex (No.3), Gemini (No.3)
**Status:** ❌ Not solved

**Problem:** `visual_resources_editor_toolbar.gd` manually instantiates the popup window and adds it to the editor's base control. This leads to "floating window" issues where the editor fails to properly track window state across sessions or layout changes. Can also lead to memory leaks if `close_requested` signals and tree exits aren't handled perfectly.

**Fix (Gemini / Codex):** Use Godot's `EditorInterface` to register the tool as a proper editor Dock, or use a dedicated `EditorWindow` subclass that integrates tightly with the engine's built-in layout and docking system.

---

### 8. O(N) Linear Scan in Change Detection

**Proposed by:** Claude (Ugly No.1)
**Status:** ❌ Not solved (intentional — low priority)

**Problem:** The inner loop `for i in updated_class_resources.size(): if path == ...` in `ResourceRepository.scan_for_changes()` does a linear search to find and replace a modified resource. With 1000+ resources and frequent filesystem events this adds up.

**Fix:** A `Dictionary[String, int]` mapping path to index would make this O(1).

**Note:** The debounce in `EditorFileSystemListener` makes this fire at most once per debounce window, and resources are already paginated. Low value unless the project scales to very large resource sets.

---

### 9. Strict MVVM (ViewModel Layer)

**Proposed by:** Claude (Ugly No.2)
**Status:** ❌ Not solved (intentional — too much work)

**Problem:** UI components bind directly to domain objects. `ResourceRow` knows what a `Resource` is, what `ResourceProperty` is, and holds a reference to `VREStateManager`. In strict MVVM, `ResourceRow` would only know about a `ResourceItemViewModel` — a plain data struct with display strings — and have zero knowledge of Godot's domain objects.

**Fix:** Ground-up rethink of data flow through the plugin. Worthwhile only if the plugin grows into a large, long-lived tool.

---

## Priority Ranking

| # | Item | Proposed by | Status | Effort | Impact |
|---|------|-------------|--------|--------|--------|
| 1 | ~~Split StateManager internally~~ | Claude / Codex / Gemini | ✅ Done | High | Critical |
| 2 | ~~EditorFilesystemListener decoupling~~ | Claude | ✅ Done | Low | Medium |
| 3 | Centralize saves + acknowledge mtimes | Claude / Codex | ❌ Open | Medium | High — fixes inspector reset on save |
| 4 | Narrow state_manager injection | Claude / Gemini | ❌ Open | Medium | Medium — testability, clean deps |
| 5 | Manual window lifecycle | Codex / Gemini | ❌ Open | Medium | Medium — stability |
| 6 | Synchronous scanning bottlenecks | Codex / Gemini | ❌ Open | High | Medium — profile first |
| 7 | Rigid %UniqueName coupling | Codex / Gemini | ❌ Disagree | Low | Low |
| 8 | O(N) linear scan | Claude | ❌ Open | Low | Low — only at scale |
| 9 | Strict MVVM | Claude | ❌ Skip | Very high | Low for current scope |
