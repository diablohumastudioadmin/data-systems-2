# Visual Resources Editor — Pending Work

## Bug Fixes

### Bulk Edit broken (item 2)
`BulkEditProxy` is dead code — never imported or used anywhere. `_start_bulk_edit_all` instead
creates a real instance of the resource class as proxy, which exposes all fields (not one at a time).
`BulkEditProxy.value_changed` signal is never connected.

**Options:**
- A) Delete `bulk_edit_proxy.gd`. Current approach (full-class proxy) works for bulk-editing all
  fields at once. Wire `_on_inspector_property_edited` to handle it correctly.
- B) Use `BulkEditProxy` properly: clicking a column header creates a single-field proxy for that
  column. `value_changed` signal propagates to all selected rows.

**Chosen approach:** TBD.

### Shift-deselect leaves bulk edit active (item 3)
In `_on_row_clicked`, the `elif not shift_held` guard means that shift-clicking to deselect rows
down to 1 never calls `_end_bulk_edit()`. Inspector keeps showing the proxy with 1 item selected.

**Fix:**
```gdscript
var selected: Array = _get_selected_rows()
if selected.size() >= 2:
	_start_bulk_edit_all(selected)
else:
	_end_bulk_edit()  # unconditional — always end when fewer than 2 selected
```

## Architecture / Design

### Auto-save bypasses undo/redo (item 6)
`_on_inspector_property_edited` calls `ResourceSaver.save()` immediately. No undo, no unsaved
indicator, no recovery from accidental edits.

**Fix:** Use `EditorUndoRedoManager` via `EditorInterface.get_editor_undo_redo()`. Wrap each
save in `create_action` / `add_do_property` / `add_undo_property` / `commit_action`.

## Missing Features

### No keyboard navigation (item 15)
No up/down arrow keys, no Delete key, no Enter to inspect. Mouse-only.

**Fix:** Override `_input` in `resource_list.gd`, check for `ui_up`/`ui_down`/`ui_cancel`.
Add `_move_selection(delta: int)` that finds the currently selected row index and selects
the adjacent one, calling `_on_row_clicked`.

### No search/filter (item 16)
With 50+ resources the list is unusable without filtering.

**Fix:** Add a `LineEdit` to the toolbar in `resource_list.tscn`. Connect `text_changed` to
a filter function that sets `row.visible = text.is_empty() or path.contains(text)`.

### No "mixed values" indicator in bulk edit (item 17)
Bulk proxy always shows first selected resource's values. If other selected resources differ,
there's no indication.

**Fix:** Before initializing the proxy, check if all selected resources agree on each field.
If not, leave that field at its default (empty/zero). Optionally add a tooltip or label.

