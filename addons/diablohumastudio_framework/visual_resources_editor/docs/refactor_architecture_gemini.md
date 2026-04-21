# Architectural Analysis: MVVM Refactoring Options

This document provides a deep analysis of the proposed architectural changes to transition the `visual_resources_editor` into a "real MVVM" architecture, addressing the problem of excessive VM-to-VM dependencies.

## The Core Problem: VM-to-VM Dependencies
In a pure MVVM architecture, ViewModels should ideally be independent of one another. When multiple VMs need to share state (like `Selected Class` or `Selected Resources`), horizontal dependencies emerge. If unmanaged, this creates a tangled web (spaghetti code) that is hard to test and maintain.

The ideas proposed address this issue directly. Here is an analysis of each option.

---

## Option 1: The `SessionStateModel` (Shared View State)
**Concept:** Extracting shared UI properties (Selection, Current Class, Filters) into a `SessionStateModel`. This acts as a Model, meaning VMs only depend downwards on Models, eliminating horizontal VM-VM dependencies.

**Deep Analysis:**
This is a highly effective and standard architectural pattern. In complex UI applications, state is generally divided into two categories:
1. **Domain State (Domain Models):** The actual data (Classes, Resource Instances on disk).
2. **Session/View State (Session Models):** Ephemeral UI data (What is selected? What page are we on? What is the current search string?).

By formalizing the Session State as a Model (e.g., `EditorSessionModel`), you achieve strict downward dependency:
- `View` depends on `ViewModel`
- `ViewModel` depends on `DomainModel` and `SessionModel`

**Pros:**
- Completely eliminates horizontal VM-to-VM dependencies.
- Highly testable (you can mock the SessionModel).
- Clear, unidirectional data flow.

**Cons:**
- The `SessionModel` can become a "dumping ground" if not carefully scoped.

**Recommendation:** **Strongly Recommended.** This is the cleanest way to share state like "Selected Resources" across the Toolbar, ResourceList, and BulkEditor without them knowing about each other.

---

## Option 2: VM Coordinator / Router (Mediator Pattern)
**Concept:** Keeping a central coordinator (similar to the current `state_manager`) but specifically for routing between VMs.

**Deep Analysis:**
Instead of VMs holding references to each other, they publish events to a central Coordinator (or Event Bus), which then updates the appropriate VMs.

**Pros:**
- Decouples VMs from direct references to one another.
- Centralizes the logic of "when X happens, update Y".

**Cons:**
- **Obscured Data Flow:** It can quickly lead to "event spaghetti" where it's difficult to trace why a VM's state changed.
- **State Duplication:** If the Coordinator tells VM_B that VM_A changed the selection, VM_B now has to store its own copy of the selection.

**Recommendation:** **Use for Commands, not State.** A Coordinator is excellent for handling *actions* (e.g., showing a dialog, triggering a global save), but the `SessionStateModel` (Option 1) is much better for managing *shared state*. Combining both is powerful: VMs read state from the `SessionStateModel` and send commands to a `CommandCoordinator`.

---

## Option 3: Single Domain Model vs. Two Domain Models
**Concept:** Should `Project Resource Classes` and `Resource Instances` remain separate models, or be combined into a single domain model?

**Deep Analysis:**
Currently, they represent two very different concepts: class definitions (metadata) and actual `.tres` files (data). 

**Pros of Single Model (Facade):**
- Simplifies ViewModel logic. VMs don't need to query the Class Model and then the Instance Model to combine data; they just ask one `ResourceDatabase` or `DomainFacade`.
- Easier to manage internal consistency (e.g., when a class is deleted, the single model automatically handles invalidating the instances).

**Pros of Two Models:**
- Strict Single Responsibility Principle.

**Recommendation:** **Use a Domain Facade.** Keep the underlying logic separated (e.g., a `ClassScanner` and a `ResourceRepository` internally), but wrap them in a single `ProjectDomainModel` facade. ViewModels should only talk to this facade. This mirrors your current `VREStateManager`'s role, but restricted purely to *Domain* data, devoid of UI state.

---

## Option 4: A ViewModel for the Resource Row
**Concept:** Having a specific VM (`ResourceRowVM`) for each individual row in the ResourceList, rather than letting `ResourceListVM` handle everything.

**Deep Analysis:**
In pure MVVM handling lists/collections, the standard practice is indeed to have a `ListVM` that contains a collection of `ItemVM`s. 

**How it works:**
- `ResourceListVM` listens to the `DomainModel` for resources and creates an array of `ResourceRowVM`s.
- `ResourceRow` (View) binds to `ResourceRowVM`.
- `ResourceRowVM` exposes clean properties for the View: `display_name`, `icon`, `is_selected`.
- When a user clicks a row, the `ResourceRowVM` updates the `SessionStateModel` to mark itself as selected.

**Pros:**
- Massively simplifies the `ResourceListVM` and the `ResourceRow` View.
- Encapsulates row-specific logic (e.g., formatting property values for display).
- Highly granular UI updates (only the row that changed needs to re-render).

**Cons:**
- Increased object allocation (creating a VM object for every row). However, since you are using Pagination, the number of active rows is small, making this a non-issue.

**Recommendation:** **Highly Recommended.** It is the most idiomatic way to handle collections in MVVM.

---

## Proposed Architecture Synthesis

Based on your ideas, here is a robust, scalable MVVM architecture:

### 1. The Model Layer (The "Truth" and the "Coordinator")
*Divided into Domain and Session, but wrapped in a single Facade.*
- **`ClassRegistry` (Domain Model)**: Handles class scanning and metadata.
- **`ResourceRepository` (Domain Model)**: Handles disk operations and `.tres` parsing.
- **`SessionStateModel` (Session Model)**: Holds all ephemeral UI state: `SelectedClass`, `SelectedResources`, `IncludeSubclasses`, `CurrentPage`, `SearchFilter`.
- **`VREModel` (The Facade/Coordinator)**: A single root object that instantiates and holds the three models above. It coordinates between them (e.g., listening to `SessionStateModel`'s `selected_class_changed` signal to trigger `ResourceRepository.load()`) and provides a unified interface for the ViewModels. ViewModels ONLY talk to the `VREModel`.

### 2. The ViewModel Layer (The "Adapters")
*VMs only depend on the `VREModel`, NEVER on other VMs.*
1. **`ClassSelectorVM`**: Binds to `VREModel` (to get classes) and updates `SelectedClass`.
2. **`SubclassFilterVM`**: Binds to `VREModel` to read/update `IncludeSubclasses`.
3. **`ToolbarVM`**: Reads `VREModel` session state to know what actions are valid. Executes Commands.
4. **`ResourceListVM`**: Generates a list of `ResourceRowVM`s based on the current page and selected class from `VREModel`.
5. **`ResourceRowVM`**: Wraps a single Resource Instance. Knows how to format data for the row. Updates selection in `VREModel` when clicked.
6. **`PaginationBarVM`**: Reads total resources and page state from `VREModel` to handle pagination logic.
7. **`StatusLabelVM`**: Reads resource counts and selection counts from `VREModel`.
8. **`BulkEditVM`**: Reads `SelectedResources` and class schema from `VREModel` to manage inspector properties.
9. **`SaveResourceDialogVM`**: Reads `SelectedClass` from `VREModel` to determine what to create.
10. **`ConfirmDeleteDialogVM`**: Reads pending deletions from `VREModel`.
11. **`ErrorDialogVM`**: Listens to error signals from `VREModel`.

### 3. The Command / Coordinator Layer (Optional but helpful)
- **`EditorCoordinator`**: Instead of VMs directly calling functions on models to delete files or show dialogs, they dispatch commands (e.g., `RequestDeleteSelection`). The Coordinator listens, shows the `ConfirmDeleteDialog`, and then tells the `VREModel` to execute the deletion.

### Conclusion
Your instincts are completely correct. The transition to a `SessionStateModel` is the exact remedy for VM-to-VM dependency hell. Combining that with `ResourceRowVM`s and wrapping the Domain and Session models within a central `VREModel` facade will result in a highly cohesive, maintainable, true MVVM architecture.

---

## Migration Plan: From Current State to New MVVM

Migrating a core plugin architecture requires a phased, incremental approach to ensure the editor remains functional and we don't end up in "refactoring hell" with a broken codebase for weeks.

### Phase 1: Foundation (The Model Layer)
**Goal:** Establish the new sources of truth without breaking the existing UI.
1. **Create `SessionStateModel`**: Create `session_state_model.gd`. Move all ephemeral state properties (e.g., `selected_class`, `selected_resources`, `include_subclasses`, `current_page`, `search_filter`) from the current `state_manager.gd` into this new class. Provide getters, setters, and signals for these properties.
2. **Create `VREModel` (Facade)**: Create `vre_model.gd`. Instantiate `ClassRegistry`, `ResourceRepository`, and the new `SessionStateModel` inside it. 
3. **Wire internal coordination**: Inside `VREModel`, connect signals. For example, listen to `SessionStateModel.selected_class_changed` and trigger `ResourceRepository.load_resources(new_class)`.
4. **Adapter Step**: Temporarily make the existing `state_manager.gd` act as a proxy to `VREModel` so the current UI doesn't break during the transition.

### Phase 2: Building the ViewModels
**Goal:** Create the ViewModels and bind them to the `VREModel`.
1. **Scaffold the VMs**: Create the 11 ViewModel scripts (e.g., `class_selector_vm.gd`, `toolbar_vm.gd`, etc.).
2. **Implement `ResourceRowVM`**: Create `resource_row_vm.gd`. This is crucial for the list migration.
3. **Connect VMs to `VREModel`**: In each VM, implement the logic to read from and listen to `VREModel`. Expose clean, UI-ready properties and signals (e.g., `ToolbarVM` exposing an `is_delete_enabled` property based on `VREModel.get_selected_resources().size() > 0`).

### Phase 3: The View Migration (Incremental UI Updates)
**Goal:** Move each UI component to use its new ViewModel instead of the old `state_manager`. Do this *one component at a time*.
1. **Migrate `ClassSelector`**: Update the view to receive and bind to `ClassSelectorVM`. Test it.
2. **Migrate `SubclassFilter` and `PaginationBar`**: Update views to use `SubclassFilterVM` and `PaginationBarVM`. Test them.
3. **Migrate `Toolbar` and `StatusLabel`**: Update to use `ToolbarVM` and `StatusLabelVM`. Test them.
4. **Migrate `ResourceList`**: This is the biggest change. Update `ResourceList` to use `ResourceListVM`. Refactor the instantiation of rows to use `ResourceRowVM` and pass the row VM to the row view. Test selection and rendering.
5. **Migrate the rest**: Update `BulkEdit`, `SaveResourceDialog`, `ConfirmDeleteDialog`, and `ErrorDialog` to their respective VMs.

### Phase 4: Commands and Cleanup
**Goal:** Finalize the architecture and remove legacy code.
1. **Implement `EditorCoordinator` (Optional but recommended)**: Extract actions (save, delete, refresh) from the UI/VMs and route them through the Coordinator.
2. **Remove `state_manager.gd`**: Once no Views or legacy components are referencing the old state manager, safely delete it.
3. **Final Polish**: Review signals, ensure there are no memory leaks, and verify that VM-to-VM dependencies are completely eliminated.