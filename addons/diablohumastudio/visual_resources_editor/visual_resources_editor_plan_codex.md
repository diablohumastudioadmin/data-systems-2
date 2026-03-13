# Visual Resources Editor — Implementation Plan

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

## Todo For Later

- M2: Scan performance improvements (leave for later).
- M7: Avoid class selector reset on data changes (leave for later).
- C1: Undo/redo for file deletion (leave for later).
- MF1: Keyboard navigation (leave for later).
- MF2: Search/filter (leave for later).
