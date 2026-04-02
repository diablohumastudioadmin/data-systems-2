# VRE New Architecture — Fixes

Consolidated list from Claude, Codex, and Gemini analyses. Items that appear in multiple analyses are merged.

---

### 1. God-Object `VREStateManager` (internal split)

**Proposed by:** Claude, Codex, Gemini
**Status:** ✅ Solved

**Problem:** `VREStateManager` handled class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic, filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and 12 signals — at least 6 distinct responsibilities in one file.

**Fix:** Split into focused `RefCounted` sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`). `VREStateManager` is now a thin coordinator (~170 LOC) that wires them together and exposes the same public API to UI.

---

### 3. `EditorFileSystemListener` Decoupling

**Proposed by:** Claude (Worth No.1)
**Status:** ✅ Solved

**Problem:** Despite having a `core/editor_filesystem_listener.gd`, the old `VREStateManager` still connected directly to `EditorInterface.get_resource_filesystem()` signals in `_ready()`.

**Fix:** All filesystem signal handling now routes through `EditorFileSystemListener`. It emits `filesystem_changed` and `script_classes_updated`. `VREStateManager` subscribes to those, decoupling the data layer from the Godot editor interface.
