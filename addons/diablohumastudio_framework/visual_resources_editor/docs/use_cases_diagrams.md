# Visual Resources Editor - Use Cases & Sequence Diagrams

---

## 1. Lifecycle

- **Case 1.1:** Plugin is installed — toolbar menu becomes visible in the Godot editor.
- **Case 1.2:** User opens the editor window from the toolbar menu.
- **Case 1.3:** User tries to open the editor while the window is already open.
- **Case 1.4:** User closes the editor with the window close button.
- **Case 1.5:** User closes the editor with `Esc`.

---

## 2. Initial Window State

- **Case 2.1:** User opens the window — no Resource classes exist in the project, the dropdown is empty.

---

## 3. Class Selection & Filtering

- **Case 3.1:** User selects a class for the first time.
- **Case 3.2:** User changes from one selected class to another.
- **Case 3.3:** User toggles `Include Subclasses` on.
- **Case 3.4:** User toggles `Include Subclasses` off.
- **Case 3.5:** User presses `Refresh` with a class selected.
- **Case 3.6:** User changes class while some rows are selected.
- **Case 3.7:** User changes class while viewing a page other than the first.
- **Case 3.8:** User changes class while a sort column is active.
- **Case 3.9:** User selects a class that has zero resources.

---

## 4. Sorting & Pagination

- **Case 4.1:** User clicks the `File` column header to sort by file name.
- **Case 4.2:** User clicks the same column header again to reverse sort direction.
- **Case 4.3:** User clicks a property column header to sort by that property.
- **Case 4.4:** User clicks a different column header while another sort is active.
- **Case 4.5:** User clicks `Next Page`.
- **Case 4.6:** User clicks `Previous Page`.
- **Case 4.7:** User clicks `Next Page` and reaches the last page.

---

## 5. Row Selection

- **Case 5.1:** User single-clicks a row when nothing is selected — resource appears in the Inspector.
- **Case 5.2:** User single-clicks a different row when one row was already selected.
- **Case 5.3:** User `Ctrl`/`Cmd`-clicks an unselected row — it is added to the selection and the Inspector updates.
- **Case 5.4:** User `Ctrl`/`Cmd`-clicks a selected row to remove it from the selection.
- **Case 5.5:** User `Shift`-clicks a row after another row was clicked (range select).
- **Case 5.6:** User `Shift`-clicks a row with no prior selection anchor.
- **Case 5.7:** User deselects all rows — Inspector panel clears.

---

## 6. Inspector & Bulk Edit

- **Case 6.1:** User edits a property in the Inspector with one resource selected.
- **Case 6.2:** User edits a property in the Inspector with multiple same-class resources selected.
- **Case 6.3:** User edits a property in the Inspector while resources of different subclasses are selected.
- **Case 6.4:** User edits a property and a save error occurs — error dialog appears.

---

## 7. Create Resource

- **Case 7.1:** User clicks `Create New` — save dialog opens.
- **Case 7.2:** User selects a save path and confirms — resource is created and appears in the list.
- **Case 7.3:** User attempts to create a resource but saving fails — error dialog appears.
- **Case 7.4:** User saves to a path where a file already exists.
- **Case 7.5:** User cancels the save dialog.

---

## 8. Delete Resource

- **Case 8.1:** User clicks `Delete Selected` from the toolbar — confirmation dialog appears.
- **Case 8.2:** User clicks the inline delete button on a row — confirmation dialog appears.
- **Case 8.3:** User confirms deletion — all selected resources are removed from the list.
- **Case 8.4:** User confirms deletion and some files cannot be deleted — error dialog appears.
- **Case 8.5:** User cancels the confirmation dialog — nothing is deleted.

---

## 9. Resource Filesystem Changes While Window Is Open

- **Case 9.1:** A resource of the currently selected class is created externally — a new row appears in the list.
- **Case 9.2:** A resource of a descendant class is created externally while `Include Subclasses` is on — a new row appears.
- **Case 9.3:** A resource of a non-selected class is created externally — the list is unaffected.
- **Case 9.4:** A resource visible on the current page is modified externally — the row updates.
- **Case 9.5:** A resource of the selected class is modified externally while not visible on the current page.
- **Case 9.6:** A resource visible on the current page is deleted externally — the row disappears.
- **Case 9.7:** A resource that is currently selected is deleted externally.
- **Case 9.8:** All resources of the currently selected class are deleted externally — the list goes empty.
- **Case 9.9:** A list reload occurs and all previously selected resources are still present — selection is restored.
- **Case 9.10:** A list reload occurs and some previously selected resources no longer exist — partial selection remains.

---

## 10. Script Class Changes While Window Is Open

- **Case 10.1:** A new Resource class is added to the project — it appears in the class dropdown.
- **Case 10.2:** A non-selected class is removed from the project.
- **Case 10.3:** The currently selected class is deleted — the list clears and the class is removed from the dropdown.
- **Case 10.4:** The currently selected class is renamed — the dropdown and list update to the new name.
- **Case 10.5:** A non-selected class is renamed.
- **Case 10.6:** The currently selected class gains a new exported property — a new column appears in the list.
- **Case 10.7:** The currently selected class loses an exported property — the column is removed from the list.
- **Case 10.8:** The currently selected class changes a property type — the column reflects the new type.
- **Case 10.9:** A descendant included class changes its exported properties while `Include Subclasses` is on.
- **Case 10.10:** A non-included class changes its exported properties — the current view is unaffected.
- **Case 10.11:** A class gains inheritance from the currently selected class while `Include Subclasses` is on — its resources appear in the list.
- **Case 10.12:** A class loses inheritance from the currently selected class while `Include Subclasses` is on — its resources disappear from the list.
- **Case 10.13:** A class is deleted while resource files of that class still exist.
- **Case 10.14:** The property being used as the active sort column is removed from the class — sort resets to file name.

---

## 11. UI Feedback

- **Case 11.1:** User makes or changes a selection — status label updates to reflect the selected count.
- **Case 11.2:** User changes selection — toolbar buttons enable or disable accordingly.
- **Case 11.3:** User changes the selected class — toolbar buttons enable or disable accordingly.
- **Case 11.4:** Total resources fit on one page — pagination bar hides. Resources exceed one page — pagination bar appears.

---

## Actors

- `User`
- `Godot Editor`
- `ClassSelectorView` — dropdown + Include Subclasses checkbox
- `ResourceListView` — toolbar + header row + resource rows + pagination bar + status label
- `ViewModel Layer`
- `Model Layer`
- `Filesystem`

---

## Diagrams

One sequence diagram per case. Diagrams use the actor set above and stay implementation-agnostic.

### Section 1 — Lifecycle

#### Case 1.1 — Plugin is installed, toolbar menu becomes visible

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    User->>Godot: Install plugin
    Godot->>Godot: Load plugin entry, register toolbar menu item
    Godot-->>User: Toolbar menu visible
```

#### Case 1.2 — User opens the editor window

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant Window as Window
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>Godot: Click toolbar menu item
    Godot->>Window: Instantiate window
    Window->>CS: Create ClassSelector
    Window->>RL: Create ResourceList
    Window->>VM: Initialize
    VM->>CR: Initialize
    CR->>CR: Scan project for Resource classes
    CR-->>VM: Available class list
    VM-->>CS: Populate dropdown
    CS-->>VM: No class selected
    VM->>RR: Initialize
    RR-->>RL: Empty list, status "0 resources"
    Window-->>User: Window shown (dropdown filled, list empty)
```

#### Case 1.3 — User opens the editor while window is already open

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant Window as Window
    User->>Godot: Click toolbar menu item
    Godot->>Window: Request open
    Window->>Window: Detect already visible
    Window-->>User: Bring existing window to front
```

#### Case 1.4 — User closes the editor with the window close button

```mermaid
sequenceDiagram
    actor User
    participant Window as Window
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>Window: Click close button
    Window->>CS: Tear down
    Window->>RL: Tear down
    Window->>VM: Tear down
    VM->>Model: Tear down
    Model->>Model: Unsubscribe from filesystem events
    Window-->>User: Window closed
```

#### Case 1.5 — User closes the editor with Esc

```mermaid
sequenceDiagram
    actor User
    participant Window as Window
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>Window: Press Esc
    Window->>Window: Detect Esc keypress
    Window->>CS: Tear down
    Window->>RL: Tear down
    Window->>VM: Tear down
    VM->>Model: Tear down
    Model->>Model: Unsubscribe from filesystem events
    Window-->>User: Window closed
```

---

### Section 2 — Initial Window State

#### Case 2.1 — User opens window, no Resource classes exist in the project

```mermaid
sequenceDiagram
    actor User
    participant Window as Window
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>Window: Open window
    Window->>CS: Initialize
    CS->>VM: Request available classes
    VM->>CR: Get available classes
    CR->>CR: Scan project — no Resource scripts found
    CR-->>VM: Empty class list
    VM-->>CS: Empty dropdown
    CS-->>VM: No class selected
    VM->>RR: No class to load
    RR-->>RL: Empty list
    Window-->>User: Window shown — dropdown empty, no class can be selected
```

---

### Section 3 — Class Selection & Filtering

#### Case 3.1 — User selects a class for the first time

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>CS: Pick class from dropdown
    CS->>VM: Class selected
    VM->>CR: Read class properties (columns)
    CR-->>VM: Column definitions
    VM->>RR: Load resources for selected class
    RR->>RR: Find and load resource files
    RR-->>VM: Resources ready
    VM-->>RL: Build header, build rows
    RL-->>User: List shows resources with class columns
```

#### Case 3.2 — User changes from one selected class to another

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>CS: Pick different class from dropdown
    CS->>VM: Class changed
    VM->>VM: Discard previous sort, page, selection
    VM->>CR: Read new class properties (columns)
    CR-->>VM: New column definitions
    VM->>RR: Load resources for new class
    RR->>RR: Discard previous, find and load new resources
    RR-->>VM: New resources ready
    VM-->>RL: Replace header, replace rows
    RL-->>User: List shows new class resources
```

#### Case 3.3 — User toggles Include Subclasses ON

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>CS: Check "Include Subclasses"
    CS->>VM: Subclass filter on
    VM->>CR: Get descendant classes of selected class
    CR-->>VM: Included class list (selected + descendants)
    VM->>CR: Merge column set across included classes
    CR-->>VM: Unified column definitions
    VM->>RR: Load resources for included classes
    RR->>RR: Find and load resource files
    RR-->>VM: Expanded resource list
    VM-->>RL: Add rows, update header
    RL-->>User: List now includes subclass resources
```

#### Case 3.4 — User toggles Include Subclasses OFF

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant CR as ClassRegistry
    participant RR as ResourceRepository
    User->>CS: Uncheck "Include Subclasses"
    CS->>VM: Subclass filter off
    VM->>CR: Read base class properties only
    CR-->>VM: Base class column definitions
    VM->>RR: Filter to base class resources only
    RR->>RR: Drop subclass resources
    RR-->>VM: Reduced resource list
    VM-->>RL: Remove rows, update header
    RL-->>User: List shows only base class resources
```

#### Case 3.5 — User presses Refresh with a class selected

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    User->>RL: Click Refresh
    RL->>VM: Refresh requested
    VM->>Model: Force reload current class
    Model->>FS: Re-scan for resources
    FS-->>Model: Current resource paths
    Model->>FS: Reload each resource
    FS-->>Model: Fresh resource data
    Model-->>VM: Updated resource list
    VM-->>RL: Replace rows
    RL-->>User: List reflects current filesystem state
```

#### Case 3.6 — User changes class while some rows are selected

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: Some rows are currently selected
    User->>CS: Pick different class
    CS->>VM: Class changed
    VM->>Model: Set new selected class
    Model->>Model: Clear selection
    Model->>Godot: Clear Inspector
    Model->>Model: Load new class resources
    Model-->>VM: New resources, no selection
    VM-->>RL: Replace rows, clear selection highlights
    RL-->>User: New list shown, nothing selected, Inspector empty
```

#### Case 3.7 — User changes class while viewing a page other than the first

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    Note over RL: Currently on page N (N > 1)
    User->>CS: Pick different class
    CS->>VM: Class changed
    VM->>Model: Set new selected class
    Model->>Model: Reset current page to 1
    Model->>Model: Load new class resources
    Model-->>VM: New resources, page 1
    VM-->>RL: Replace rows, update pagination bar
    RL-->>User: New list shown on page 1
```

#### Case 3.8 — User changes class while a sort column is active

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    Note over RL: A sort column is active
    User->>CS: Pick different class
    CS->>VM: Class changed
    VM->>Model: Set new selected class
    Model->>Model: Load new class resources & columns
    Model->>Model: Validate sort column against new columns
    alt Sort column exists in new class
        Model->>Model: Apply existing sort
    else Sort column missing in new class
        Model->>Model: Reset sort to file name
    end
    Model-->>VM: Sorted resources, current sort state
    VM-->>RL: Replace rows, update header sort indicator
    RL-->>User: New list shown, sort applied or reset
```

#### Case 3.9 — User selects a class that has zero resources

```mermaid
sequenceDiagram
    actor User
    participant CS as ClassSelectorView
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    User->>CS: Pick class from dropdown
    CS->>VM: Class selected
    VM->>Model: Set selected class
    Model->>Model: Read class properties (columns)
    Model->>FS: Find resource files of this class
    FS-->>Model: Empty path list
    Model-->>VM: Empty resource list, columns from class definition
    VM-->>RL: Build header, no rows
    RL-->>User: Empty list with column headers, status "0 resources"
```

---

### Section 4 — Sorting & Pagination

#### Case 4.1 — User clicks the File column header to sort by file name

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>RL: Click File column header
    RL->>VM: Sort by file name requested
    VM->>Model: Set sort column = file, direction = ascending
    Model->>Model: Sort resources by file name
    Model-->>VM: Sorted resource list
    VM-->>RL: Replace rows, show sort indicator on File header
    RL-->>User: List sorted by file name ascending
```

#### Case 4.2 — User clicks the same column header again to reverse sort direction

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    Note over RL: File column is sorted ascending
    User->>RL: Click File column header again
    RL->>VM: Sort by file name requested
    VM->>Model: Toggle sort direction (ascending → descending)
    Model->>Model: Sort resources by file name descending
    Model-->>VM: Sorted resource list
    VM-->>RL: Replace rows, flip sort indicator direction
    RL-->>User: List sorted by file name descending
```

#### Case 4.3 — User clicks a property column header to sort by that property

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>RL: Click property column header
    RL->>VM: Sort by property requested
    VM->>Model: Set sort column = property, direction = ascending
    Model->>Model: Sort resources by property value
    Model-->>VM: Sorted resource list
    VM-->>RL: Replace rows, show sort indicator on property header
    RL-->>User: List sorted by property ascending
```

#### Case 4.4 — User clicks a different column header while another sort is active

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    Note over RL: Currently sorted by a different column
    User->>RL: Click new column header
    RL->>VM: Sort by new column requested
    VM->>Model: Set sort column = new column, direction = ascending
    Model->>Model: Sort resources by new column
    Model-->>VM: Sorted resource list
    VM-->>RL: Replace rows, move sort indicator to new header
    RL-->>User: List sorted by new column ascending
```

#### Case 4.5 — User clicks Next Page

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>RL: Click Next Page
    RL->>VM: Next page requested
    VM->>Model: Advance current page
    Model->>Model: Slice resources for new page
    Model-->>VM: Page rows, current page number, total pages
    VM-->>RL: Replace rows, update pagination bar
    RL-->>User: Next page of resources shown
```

#### Case 4.6 — User clicks Previous Page

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>RL: Click Previous Page
    RL->>VM: Previous page requested
    VM->>Model: Go back one page
    Model->>Model: Slice resources for previous page
    Model-->>VM: Page rows, current page number, total pages
    VM-->>RL: Replace rows, update pagination bar
    RL-->>User: Previous page of resources shown
```

#### Case 4.7 — User clicks Next Page and reaches the last page

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    User->>RL: Click Next Page
    RL->>VM: Next page requested
    VM->>Model: Advance current page
    Model->>Model: Slice resources for last page
    Model-->>VM: Page rows, current page = last page
    VM-->>RL: Replace rows, disable Next Page button
    RL-->>User: Last page shown, Next Page disabled
```

---

### Section 5 — Row Selection

#### Case 5.1 — User single-clicks a row when nothing is selected

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    User->>RL: Click row
    RL->>VM: Row clicked (single select)
    VM->>Model: Set selection = [clicked resource]
    Model-->>VM: Selection updated
    VM->>Godot: Show resource in Inspector
    VM-->>RL: Highlight clicked row
    RL-->>User: Row highlighted, resource visible in Inspector
```

#### Case 5.2 — User single-clicks a different row when one row was already selected

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: One row is currently selected
    User->>RL: Click different row
    RL->>VM: Row clicked (single select)
    VM->>Model: Set selection = [new resource]
    Model-->>VM: Selection updated
    VM->>Godot: Show new resource in Inspector
    VM-->>RL: Move highlight to new row
    RL-->>User: New row highlighted, Inspector updated
```

#### Case 5.3 — User Ctrl/Cmd-clicks an unselected row

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: One or more rows already selected
    User->>RL: Ctrl-click unselected row
    RL->>VM: Row ctrl-clicked (toggle)
    VM->>Model: Add resource to selection
    Model-->>VM: Selection updated
    VM->>Godot: Update Inspector for multi-selection
    VM-->>RL: Add highlight to clicked row
    RL-->>User: Multiple rows highlighted, Inspector shows shared properties
```

#### Case 5.4 — User Ctrl/Cmd-clicks a selected row to remove it from selection

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: Multiple rows selected
    User->>RL: Ctrl-click selected row
    RL->>VM: Row ctrl-clicked (toggle)
    VM->>Model: Remove resource from selection
    Model-->>VM: Selection updated
    VM->>Godot: Update Inspector for remaining selection
    VM-->>RL: Remove highlight from clicked row
    RL-->>User: Row deselected, Inspector updated
```

#### Case 5.5 — User Shift-clicks a row after another row was clicked (range select)

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: A row was previously clicked (anchor)
    User->>RL: Shift-click another row
    RL->>VM: Row shift-clicked (range)
    VM->>Model: Set selection = range from anchor to clicked row
    Model-->>VM: Selection updated
    VM->>Godot: Update Inspector for range selection
    VM-->>RL: Highlight all rows in range
    RL-->>User: Range of rows highlighted, Inspector shows shared properties
```

#### Case 5.6 — User Shift-clicks a row with no prior selection anchor

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    User->>RL: Shift-click row (no prior anchor)
    RL->>VM: Row shift-clicked (no anchor)
    VM->>Model: Set selection = [clicked resource]
    Model-->>VM: Selection updated
    VM->>Godot: Show resource in Inspector
    VM-->>RL: Highlight clicked row
    RL-->>User: Row highlighted, resource visible in Inspector
```

#### Case 5.7 — User deselects all rows

```mermaid
sequenceDiagram
    actor User
    participant RL as ResourceListView
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant Godot as Godot Editor
    Note over RL: One or more rows selected
    User->>RL: Click empty area / deselect action
    RL->>VM: Deselect all
    VM->>Model: Clear selection
    Model-->>VM: Selection empty
    VM->>Godot: Clear Inspector
    VM-->>RL: Remove all highlights
    RL-->>User: No rows highlighted, Inspector empty
```

---

### Section 6 — Inspector & Bulk Edit

#### Case 6.1 — User edits a property in the Inspector with one resource selected

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    participant RL as ResourceListView
    User->>Godot: Edit property in Inspector
    Godot->>VM: Property changed on resource
    VM->>Model: Save resource
    Model->>FS: Write resource to disk
    FS-->>Model: Save confirmed
    Model-->>VM: Resource updated
    VM-->>RL: Update row with new value
    RL-->>User: Row reflects edited property
```

#### Case 6.2 — User edits a property in the Inspector with multiple same-class resources selected

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    participant RL as ResourceListView
    Note over Godot: Multiple same-class resources selected
    User->>Godot: Edit property in Inspector
    Godot->>VM: Property changed (bulk)
    VM->>Model: Apply change to all selected resources
    loop Each selected resource
        Model->>FS: Write resource to disk
        FS-->>Model: Save confirmed
    end
    Model-->>VM: All resources updated
    VM-->>RL: Update affected rows
    RL-->>User: All selected rows reflect new value
```

#### Case 6.3 — User edits a property in the Inspector while resources of different subclasses are selected

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    participant RL as ResourceListView
    Note over Godot: Resources of different subclasses selected
    User->>Godot: Edit property in Inspector
    Godot->>VM: Property changed (bulk, mixed classes)
    VM->>Model: Apply change only to resources that have this property
    loop Each resource with matching property
        Model->>FS: Write resource to disk
        FS-->>Model: Save confirmed
    end
    Model-->>VM: Matching resources updated
    VM-->>RL: Update affected rows (non-matching rows unchanged)
    RL-->>User: Matching rows reflect new value, others unchanged
```

#### Case 6.4 — User edits a property and a save error occurs

```mermaid
sequenceDiagram
    actor User
    participant Godot as Godot Editor
    participant VM as ViewModel Layer
    participant Model as Model Layer
    participant FS as Filesystem
    participant RL as ResourceListView
    User->>Godot: Edit property in Inspector
    Godot->>VM: Property changed on resource
    VM->>Model: Save resource
    Model->>FS: Write resource to disk
    FS-->>Model: Save failed (error)
    Model-->>VM: Save error
    VM-->>RL: Show error dialog
    RL-->>User: Error dialog appears
```