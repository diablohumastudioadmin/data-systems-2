# VRE Architecture Refactor — Extreme Clean Proposal

This proposal takes the deconstruction of the "God Object" to its logical conclusion: **Removing `VREModel` entirely** and flattening the architecture into a direct Service-to-VM relationship.
# VRE Architecture Refactor — Extreme Clean Proposal

## 🏁 ARCHITECTURE VISION & FINAL CONCLUSIONS

Based on our architectural deep-dive, here is the final blueprint for the VRE refactor:

1.  **Eliminate the "Middleman"**: `VREModel` and `VREStateManager` are deleted. They are redundant proxies that create unnecessary signal-hopping.
2.  **Power to the List**: `ResourceListVM` becomes the central orchestrator of the data grid. It directly owns **Pagination**, **Selection**, and **Sorting** (using a utility).
3.  **UI Consolidation**: `PaginationBar` and `StatusLabel` move *inside* the `ResourceList` scene. This encapsulates the entire list experience into a single, self-sufficient component.
4.  **Keep the "Source of Truth"**: `SessionStateModel` remains as a lightweight object representing **User Intent** (`selected_class`, `sort_column`, `subclass_toggle`). It prevents "VM-to-VM dependency hell" by allowing the Selector, Toolbar, and List to stay independent while sharing the same context.
5.  **Direct Service Injection**: The `Window` instantiates domain services (`ResourceRepository`, `ClassRegistry`, `FSListener`) and injects them directly into ViewModels.
6.  **Persistence Integrity**: `ResourceRepository` is the sole owner of disk operations (Saving/Deleting), fixing the split ownership between the old Repository and BulkEditor.

---

## 1. UI Consolidation: The "Resource List" Scene
To improve encapsulation, the `PaginationBar` and `StatusLabel` will move inside the `ResourceList` scene. 
- **Reasoning**: These components exist only to support the list view. Keeping them external requires extra signal jumping.
- **New Structure**:
  ```
  ResourceList (Scene)
  ├── ScrollContainer (Main Data)
  ├── PaginationBar (Inner UI)
  └── StatusLabel (Inner UI)
  ```

---

## 2. The "Power VM": `ResourceListVM`
`ResourceListVM` becomes the primary orchestrator for the data grid. It will directly own the presentation state.

### New Responsibilities:
- **Pagination**: Owns an internal `PaginationManager`.
- **Selection**: Owns an internal `SelectionManager`.
- **Sorting**: Performs sorting via the `ResourceSorter` utility before slicing pages.
- **State Derived**: Automatically calculates `visible_count` and `total_pages` for its inner components (fixing Item 23).

### Direct Binding:
Instead of waiting for `VREModel` to forward signals, `ResourceListVM` connects directly to the `ResourceRepository`.
- `resource_repo.resources_reset` -> `_rebuild_rows()` (Sort -> Paginate -> Emit).
- `resource_repo.resources_delta` -> `_update_rows()` (Update only affected).

---

## 3. Removing `VREModel`: The "Middleman" is Dead
`VREModel` currently acts as a redundant proxy (Item 4). Removing it creates a much cleaner, flatter architecture.

### How it works:
The `VisualResourcesEditorWindow` (the entry point) instantiates the core **Services** and injects them into the **ViewModels**.

#### Dependency Injection Map:
| Component | Injected Services | Responsibilities |
|-----------|-------------------|------------------|
| **ClassSelectorVM** | `SessionStateModel`, `ClassRegistry`, `ResourceRepository` | Updates `selected_class`. Tells `ResourceRepository` to `load_resources` on change. |
| **ResourceListVM** | `SessionStateModel`, `ResourceRepository`, `ClassRegistry` | Sorts, Paginates, Selects. Displays rows. |
| **ToolbarVM** | `SessionStateModel`, `ResourceRepository` | Create/Delete/Refresh actions. |
| **BulkEditor** | `SessionStateModel`, `ResourceRepository` | Debounced saving (Item 7) via the Repository. |

### Evaluation:
- **Cleanliness**: **10/10**. No more "signal hopping" (View -> VM -> Model -> SubManager). Logic is exactly where it is used.
- **Difficulty**: **Moderate/High**. Requires re-wiring the `Window` and updating every VM's constructor. However, since the Sub-Managers already exist, it's mostly a "plumbing" task.
- **Risk**: Low, as long as the "Domain Controller" logic (like Filesystem wiring) is handled correctly.

---

## 4. The "Domain Controller" (Service Wiring)
Since `VREModel` handled the wiring between managers (e.g., `FSListener` -> `ClassRegistry`), we need a place for this. 
- **The Solution**: The `VisualResourcesEditorWindow` (or a dedicated `VREController` object) wires the services once during `_ready()`.
  - `fs_listener.classes_updated` -> `class_registry.rebuild()`
  - `fs_listener.filesystem_changed` -> `resource_repo.scan_for_changes()`
  - `class_registry.classes_changed` -> `class_selector_vm.refresh()`

---

## 5. Implementation Roadmap (Finalized)

### Phase 1: Preparation (Infrastructure)
- [ ] **Item 5a**: Extract `ResourceSorter` (Utility).
- [ ] **Item 5b**: Move property scanning/merging to `ClassRegistry`.
- [ ] **Item 20**: Fix typos (`resouce` -> `resource`).
- [ ] **Item 8**: Centralize `save_resource` inside `ResourceRepository`.

### Phase 2: VM & UI Restructuring
- [ ] Move `PaginationBar` and `StatusLabel` into `ResourceList.tscn`.
- [ ] Move `PaginationManager` and `SelectionManager` into `ResourceListVM`.
- [ ] Update `ResourceListVM` to handle the "Big Three" (Sort/Paginate/Select).
- [ ] **Item 6**: Optimize `SelectionManager` with Dictionaries.

### Phase 3: The Big Delete
- [ ] Update `VisualResourcesEditorWindow` to instantiate Services directly.
- [ ] Inject Services into VMs.
- [ ] **Delete `VREModel.gd`**.
- [ ] **Delete `VREStateManager.gd`** (Redundant proxy).

### Phase 4: Reliability & Performance
- [ ] **Item 7**: Debounce `BulkEditor` saving.
- [ ] **Item 11**: Optimize `ProjectClassScanner` using `EditorFileSystem`.
- [ ] **Item 13**: Fix StyleBox mutation in `ResourceFieldLabel`.
- [ ] **Item 15**: Delete all decorative ViewModels (`SubclassFilterVM`, `ErrorDialogVM`, etc.).
