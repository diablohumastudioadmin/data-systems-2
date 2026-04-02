# Proposal: Narrow State Manager Injection Refactor

## Background & Context
Based on the architectural analysis (FIXES Item #1 and TODOS Items #2, #4, and #7):
1. **(Item 1) Internal Split Complete:** The `VREStateManager` has successfully been split internally into focused sub-managers (`ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, `EditorFileSystemListener`).
2. **(Item 4) Injection Issue:** However, the UI still receives the *entire* `VREStateManager` coordinator. This violates the Interface Segregation Principle. We need to inject only the necessary sub-managers into each UI component.
3. **(Item 7) `%UniqueName` Conventions:** We must respect the project's `CLAUDE.md` conventions. We will *not* use `@export NodePath` or an initialization `setup()` method. We will keep `%UniqueName` references and use the property setter + `_ready()` guard pattern.
4. **(Item 2) Scattered Saves:** As we refine the injection, we must ensure that operations like bulk saving or single saving still have a clean path to update the `ResourceRepository`'s mtimes (this can remain coordinated through `VREStateManager` or a dedicated save function on `ResourceRepository`).

## The Proposed Solution

The goal is to update `VisualResourcesEditorWindow` to inject the precise sub-managers into each UI component using the established property setter pattern. 

### Step 1: Expose Sub-Managers as Public Read-Only Properties in `VREStateManager`

Currently, the sub-managers in `VREStateManager` are private variables (e.g., `var _pagination: PaginationManager`). We need to expose them so the main window can inject them:

```gdscript
# core/state_manager.gd

# ── Sub-managers (Exposed as read-only properties) ──────────
var class_registry: ClassRegistry:
    get: return _class_registry

var resource_repo: ResourceRepository:
    get: return _resource_repo

var selection: SelectionManager:
    get: return _selection

var pagination: PaginationManager:
    get: return _pagination
```

### Step 2: Refactor UI Components to Require Specific Sub-Managers

Instead of a single `var state_manager: VREStateManager` property, each UI component will declare only the sub-managers it needs, using the project's setter pattern.

**Example 1: `PaginationBar`**
```gdscript
# ui/pagination_bar/pagination_bar.gd
extends Control

var pagination: PaginationManager = null:
    set(value):
        pagination = value
        if is_inside_tree():
            _connect_pagination()

func _ready() -> void:
    if pagination:
        _connect_pagination()

func _connect_pagination() -> void:
    %PrevBtn.pressed.connect(pagination.prev)
    %NextBtn.pressed.connect(pagination.next)
    pagination.pagination_changed.connect(_on_pagination_changed)
```

**Example 2: `ResourceList`**
```gdscript
# ui/resource_list/resource_list.gd
extends Control

var resource_repo: ResourceRepository = null:
    set(value):
        resource_repo = value
        if is_inside_tree():
            _connect_repo()

var selection: SelectionManager = null:
    set(value):
        selection = value
        if is_inside_tree():
            _connect_selection()

func _ready() -> void:
    if resource_repo: _connect_repo()
    if selection: _connect_selection()

func _connect_repo() -> void:
    resource_repo.resources_replaced.connect(_on_resources_replaced)
    resource_repo.resources_added.connect(_on_resources_added)
    # ...

func _connect_selection() -> void:
    selection.selection_changed.connect(_on_selection_changed)
```

### Step 3: Update the Main Window Injector

The `VisualResourcesEditorWindow` will remain the central dependency injector. It will instantiate the main `VREStateManager` (which handles the high-level cross-component wiring) but will pass the specific sub-managers to the children using their `%UniqueName` references.

```gdscript
# ui/visual_resources_editor_window.gd
extends Window

var _state: VREStateManager

func _ready() -> void:
    _state = VREStateManager.new()
    _state.start()

    # Narrow Injection using the established setter pattern
    %ClassSelector.class_registry = _state.class_registry
    
    %SubclassFilter.coordinator = _state # Still needs high-level coordinator to set include subclasses
    
    %ResourceList.resource_repo = _state.resource_repo
    %ResourceList.selection = _state.selection
    
    %PaginationBar.pagination = _state.pagination
    
    %BulkEditor.selection = _state.selection
    %BulkEditor.coordinator = _state # Still needs to notify high-level of saves
    
    %Toolbar.selection = _state.selection
    %Toolbar.coordinator = _state
```

### Step 4: Handle "Coordinator" Actions

Some actions, like `request_create_new_resource()`, `request_delete_selected_resources()`, or `set_current_class()`, are high-level coordination tasks that span multiple sub-managers. 

For UI components that trigger these actions (like `%Toolbar`, `%ClassSelector`, or `%BulkEditor`), they should either:
1. Continue to receive a reference to the `VREStateManager` (perhaps renamed to `coordinator` locally to clarify its role).
2. Or emit custom UI signals that the `VisualResourcesEditorWindow` listens to and routes to `_state`.

Given the project's preference for direct state calls (avoiding intermediate UI signal bouncing), passing the `VREStateManager` under the name `coordinator: VREStateManager` to the few components that genuinely need to trigger high-level workflows is the cleanest approach. 

## Summary of Benefits
- **Strict Adherence to Conventions:** We avoid `@export NodePath` and `setup()` methods, keeping the `%UniqueName` and `setter` patterns intact (Item 7).
- **Testability:** Components like `%PaginationBar` can now be instantiated and tested in isolation by simply providing a mock `PaginationManager` (Item 4).
- **Reduced Coupling:** By removing the "God-Object" from components that don't need it, we eliminate the risk of unintended side effects and fully realize the benefits of the internal split done in Item 1.

---

## Deep Analysis: Gemini vs. Codex Refactor Proposal

The `refactor_injection_codex.md` file presents an alternative approach to solving the injection and coupling issues. After a rigorous and critical review of both strategies, here is a breakdown of what Codex got right, what it got wrong, and how we should synthesize the ultimate solution.

### 1. The Brilliant Insight: `BrowseSession` (Codex ✅)
**Codex identifies the fundamental blocker that the Gemini proposal initially missed.** 
In the Gemini proposal (Step 4), we conceded that components like `%ClassSelector` and `%SubclassFilter` still need the high-level `coordinator` (`VREStateManager`) to call methods like `set_current_class()`. 

Codex correctly points out that this is because `VREStateManager` is still hoarding "session state" (e.g., `_current_class_name`, `_include_subclasses`, and the cached property lists). 
**Verdict:** We **must** adopt Codex's Phase 1. Extracting `core/browse_session.gd` to own the current browsing context is a masterstroke. It cleanly separates "what classes exist" (`ClassRegistry`) from "what the user is currently looking at" (`BrowseSession`), completely eliminating the need for `ClassSelector` to depend on the central coordinator.

### 2. The Over-Engineering Trap: Facade Actions (Codex ❌)
Codex suggests creating "tiny facade wrappers" like `PageCommands`, `ResourcePageFeed`, `ToolbarActions`, and `SelectionActions`. For example, instead of injecting the `PaginationManager` into the `PaginationBar`, Codex proposes injecting a `PageCommands` wrapper that *only* exposes `next_page()` and `prev_page()`.

**Verdict:** This is severe over-engineering and introduces Java-esque interface bloat that goes against Godot's design philosophy. 
If we have already split `PaginationManager` into a tiny, focused class, injecting it directly into `PaginationBar` is perfectly acceptable. Wrapping a 50-line manager in a 10-line facade just to hide a couple of public methods adds unnecessary boilerplate, extra files, and cognitive overhead for zero tangible benefit. We will **reject** the Facade Action layer (Codex Phase 3 & 4 facades) and stick to the direct, typed injection of our core sub-managers proposed by Gemini.

### 3. Centralizing Saves: Fixing the Inspector Bounce (Codex ✅)
Codex rightly insists on moving the `ResourceSaver.save()` calls out of `BulkEditor` and `VREStateManager` into a centralized `save_resources()` method on `ResourceRepository` (or a dedicated `ResourceSaveService`).

**Verdict:** This is a critical fix for TODO Item 2. By having the repository handle the save, it can immediately update its internal `_mtimes` cache. This acts as an "acknowledgment" of the save, so when the subsequent `EditorFileSystem.filesystem_changed` signal fires, the repository recognizes the files haven't changed *externally* and aborts the UI refresh. This effectively solves the dreaded "Inspector losing focus while typing" bug.

### Final Synthesis: The Ultimate Refactor Path
To achieve the cleanest architecture, we should merge the best of both worlds:

1. **Extract `BrowseSession` (from Codex):** Move `current_class_name`, `include_subclasses`, and property caches out of `VREStateManager`.
2. **Centralize Saves (from Codex):** Add `save_resources(resources)` to `ResourceRepository` to update `_mtimes` and prevent inspector bouncing.
3. **Direct Sub-Manager Injection (from Gemini):** Inject `ResourceRepository`, `BrowseSession`, `SelectionManager`, and `PaginationManager` directly into the UI components using the `property setter + is_inside_tree()` pattern. Do **not** create unnecessary facade adapters.
4. **Preserve `%UniqueNames` (from Gemini):** Continue wiring these dependencies from the `VisualResourcesEditorWindow` via `%UniqueNames` to respect project conventions.
