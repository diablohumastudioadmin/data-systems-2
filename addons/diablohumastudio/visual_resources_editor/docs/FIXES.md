# VRE New Architecture — Fixes

Consolidated list from Claude, Codex, and Gemini analyses. Items that appear in multiple analyses are merged.

---

### 1. God-Object `VREStateManager` (internal split)

**Proposed by:** Claude, Codex, Gemini
**Status:** ✅ Solved

**Problem:** `VREStateManager` handled class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic, filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and 12 signals — at least 6 distinct responsibilities in one file.

**Fix:** Split into focused `RefCounted` sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`). `VREStateManager` is now a thin coordinator (~170 LOC) that wires them together and exposes the same public API to UI.
