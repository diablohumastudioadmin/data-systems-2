# Visual Resources Editor - Use Cases & Sequence Diagrams

Merged from: **Gemini**, **Codex**, and **Claude** analysis.
Codex provided the most granular breakdown and is used as the structural base.

---

## 1. Lifecycle

- **Case 1.1:** Plugin enters tree and registers the `VisualResourcesEditor` toolbar submenu.
- **Case 1.2:** User opens the editor window from the toolbar menu for the first time.
- **Case 1.3:** User tries to open the editor while the window is already open.
- **Case 1.4:** User closes the editor with the window close button.
- **Case 1.5:** User closes the editor with `Esc`.
- **Case 1.6:** Plugin exits while the editor window is still open.

---

## 2. Initial Window State

- **Case 2.1:** Window opens and creates `VREModel`, ViewModels, dialogs, and `BulkEditor` (full DI container setup).
- **Case 2.2:** Window opens with no selected class and therefore no resources loaded yet.
- **Case 2.3:** Window opens when **no Resource script classes exist at all** in the project (empty dropdown). *(Claude)*

---

## 3. Class Selection & Filtering

- **Case 3.1:** User selects a class for the first time.
- **Case 3.2:** User changes from one selected class to another.
- **Case 3.3:** User toggles `Include Subclasses` on for the selected class.
- **Case 3.4:** User toggles `Include Subclasses` off for the selected class.
- **Case 3.5:** User presses `Refresh` with a selected class.
- **Case 3.6:** User changes class while resources are currently selected.
- **Case 3.7:** User changes class while currently viewing a later page.
- **Case 3.8:** User changes class while a sort is active.
- **Case 3.9:** User selects a class that has zero resources. *(Claude)*

---

## 4. Sorting & Pagination

- **Case 4.1:** User clicks the `File` header to sort by file name.
- **Case 4.2:** User clicks the same header again to reverse sort order.
- **Case 4.3:** User clicks a property column header to sort by that property.
- **Case 4.4:** User clicks a different property header after another sort is already active.
- **Case 4.5:** User clicks `Next Page`.
- **Case 4.6:** User clicks `Previous Page`.
- **Case 4.7:** Current page becomes invalid after resource count changes and pagination clamps it.
- **Case 4.8:** Current sort column becomes invalid after a property-schema change and sort resets to `File`.

---

## 5. Row Selection

- **Case 5.1:** User single-clicks a row when nothing is selected.
- **Case 5.2:** User single-clicks a different row after one row was already selected.
- **Case 5.3:** User `Ctrl`/`Cmd`-clicks an unselected row to add it to the selection.
- **Case 5.4:** User `Ctrl`/`Cmd`-clicks a selected row to remove it from the selection.
- **Case 5.5:** User `Shift`-clicks a row after another row was clicked (range select).
- **Case 5.6:** User `Shift`-clicks with no valid anchor yet, so it falls back to single selection.
- **Case 5.7:** Selection is restored after a resource reload and all selected paths still exist.
- **Case 5.8:** Selection is restored after a resource reload and some selected paths no longer exist.
- **Case 5.9:** Selection becomes empty and the inspector proxy is cleared.
- **Case 5.10:** User clicks the global "Select All / Deselect All" checkbox in the header row. *(Gemini)*

---

## 6. Inspector & Bulk Edit

- **Case 6.1:** Selecting one resource makes `BulkEditor` inspect a proxy populated with that resource's values.
- **Case 6.2:** Selecting multiple resources of the same script makes `BulkEditor` inspect a common proxy.
- **Case 6.3:** Selecting multiple resources with mixed scripts makes `BulkEditor` fall back to `current_class_script`.
- **Case 6.4:** User edits one property in the inspector for a single selected resource.
- **Case 6.5:** User edits one property in the inspector for multiple selected resources.
- **Case 6.6:** User edits one property in a mixed-class selection and resources without that property are skipped.
- **Case 6.7:** Bulk edit saves succeed and `resources_edited` updates visible rows.
- **Case 6.8:** Bulk edit save fails for some resources and the error dialog is shown.
- **Case 6.9:** Selection changes but the inspected selection paths are identical, so the proxy is not rebuilt.

---

## 7. Create Resource Flow

- **Case 7.1:** User clicks `Create New` with a valid selected class and the save dialog opens.
- **Case 7.2:** User chooses a path and the resource is instantiated and saved successfully.
- **Case 7.3:** Save dialog tries to create a resource but the class script cannot be loaded.
- **Case 7.4:** Save dialog tries to create a resource but the script cannot instantiate.
- **Case 7.5:** Save dialog saves and `ResourceSaver.save` fails.
- **Case 7.6:** A newly created resource later appears through the filesystem refresh flow.
- **Case 7.7:** User saves to a path where a file already exists (overwrite scenario). *(Claude)*

---

## 8. Delete Resource Flow

- **Case 8.1:** User clicks `Delete Selected` from the toolbar.
- **Case 8.2:** User clicks the delete button on a single row.
- **Case 8.3:** Confirm-delete dialog opens with pending paths.
- **Case 8.4:** User confirms delete and all files are moved to trash successfully.
- **Case 8.5:** User confirms delete and some files fail to move to trash.
- **Case 8.6:** A pending delete path is outside `res://` and is rejected defensively.
- **Case 8.7:** User cancels the delete dialog and nothing is deleted.
- **Case 8.8:** Deleted resources disappear from the list after filesystem refresh.

---

## 9. Resource Filesystem Changes While Window Is Open

- **Case 9.1:** A `.tres` for the current selected class is created externally.
- **Case 9.2:** A `.tres` for a descendant class is created externally while `Include Subclasses` is on.
- **Case 9.3:** A `.tres` for a non-included class is created externally.
- **Case 9.4:** A visible resource on the current page is modified externally.
- **Case 9.5:** A resource in the selected class but off the current page is modified externally.
- **Case 9.6:** A visible resource on the current page is deleted externally.
- **Case 9.7:** A selected resource is deleted externally.
- **Case 9.8:** `filesystem_changed` fires but repository diff finds no relevant changes.
- **Case 9.9:** All resources of the currently selected class are deleted externally at once (list goes empty). *(Claude)*

---

## 10. Script Class Changes While Window Is Open

- **Case 10.1:** A new `Resource` script class is added and appears in the class dropdown.
- **Case 10.2:** A non-selected resource class is removed.
- **Case 10.3:** The currently selected class is removed and no rename is detected, so the view clears.
- **Case 10.4:** The currently selected class is renamed and selection follows the new class name.
- **Case 10.5:** A non-selected class is renamed.
- **Case 10.6:** The currently selected class script gains a new exported property.
- **Case 10.7:** The currently selected class script loses an exported property.
- **Case 10.8:** The currently selected class script changes a property definition or type.
- **Case 10.9:** A descendant included class changes exported properties while `Include Subclasses` is on.
- **Case 10.10:** A non-included class changes exported properties and the current view should remain unaffected.
- **Case 10.11:** A class changes inheritance and enters the selected class subtree.
- **Case 10.12:** A class changes inheritance and leaves the selected class subtree.
- **Case 10.13:** A class is removed and orphaned resources are re-saved to clean their script reference.

---

## 11. UI Feedback & Derived State

- **Case 11.1:** Error message from any operation is routed through `ErrorDialogVM` to the error dialog.
- **Case 11.2:** Status label changes from `N resource(s)` to `N selected`.
- **Case 11.3:** Toolbar action enablement changes when selection changes.
- **Case 11.4:** Toolbar action enablement changes when selected class changes.
- **Case 11.5:** Pagination bar hides when only one page exists and shows when more than one page exists.
