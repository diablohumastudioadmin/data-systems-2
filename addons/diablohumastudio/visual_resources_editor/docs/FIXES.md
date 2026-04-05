# VRE New Architecture — Fixes

Consolidated list from Claude, Codex, and Gemini analyses. Items that appear in multiple analyses are merged.

---

### 1. God-Object `VREStateManager` (internal split)

**Proposed by:** Claude, Codex, Gemini
**Status:** ✅ Solved

**Problem:** `VREStateManager` handled class maps, resource scanning, mtime caching, pagination arithmetic, multi-select logic, filesystem event routing, class rename detection, orphaned resource resaving, property change detection, and 12 signals — at least 6 distinct responsibilities in one file.

**Fix:** Split into focused `RefCounted` sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`). `VREStateManager` is now a thin coordinator (~170 LOC) that wires them together and exposes the same public API to UI.

---

### 2. VM-to-VM Dependency Hell (MVVM refactor)

**Status:** ✅ Solved

**Problem:** Five ViewModels depended on `ClassSelector VM → Selected Class`
and three depended on `SubclassFilter VM → Include Subclasses`, creating
horizontal VM-to-VM coupling that is hard to test and violates MVVM's
unidirectional dependency rule.

**Fix:** Introduced `SessionStateModel` in the Model layer to own all shared
session state (`selected_class`, `include_subclasses`, `selected_resources`,
`current_page`). All VMs read session state from `VREModel` (which exposes
`SessionStateModel` internally). VM-to-VM dependencies are fully eliminated.

---

### 3. Full MVVM Layer Implementation

**Status:** ✅ Solved

**Problem:** All UI components held a reference to the full `VREStateManager`
god object, binding directly to domain objects with no separation layer.

**Fix:** Implemented a complete ViewModel layer (`view_models/`). Each View now
binds to a dedicated ViewModel. `VisualResourcesEditorWindow` creates all VMs
and injects them. Key decisions:

- `SessionStateModel` (Model layer) eliminates VM-to-VM dependencies.
- `BulkEditor` connects directly to `VREModel` — it is a non-visual service,
  not a View, so no ViewModel is needed or useful.
- `ResourceRowVM` (per-row VM) simplifies `ResourceListVM` and removes the
  global selection sweep in `ResourceList`.

See `architecture_analisys.md §I–L` for full decision rationale.
