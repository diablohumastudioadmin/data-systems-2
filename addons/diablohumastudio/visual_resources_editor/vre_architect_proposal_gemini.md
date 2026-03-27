# Visual Resources Editor - Comprehensive Architecture Proposal

This document outlines a transition from a monolithic `VREStateManager` to a clean, decoupled architecture based on the Model-View-Presenter (MVP) / Clean Architecture pattern adapted for the Godot Editor.

## 1. Core Objectives

1.  **Decoupling State from Disk/Editor:** `VREStateManager` should not know about `EditorFileSystem`, `FileAccess`, `ProjectSettings`, or disk paths. It should only care about application state (what is selected, what page we are on).
2.  **Testability:** By abstracting data access into Repositories through Interfaces, we can inject "Dummy" repositories to unit test the state manager without booting the Godot Editor or touching the disk.
3.  **Single Responsibility Principle:** Debouncing and editor signal listening should live in one place. Disk scanning should live in another. UI state should live in another.

## 2. The Dependency Flow

The system will be composed of four distinct layers:

```text
[ Data Layer ] -> [ Coordination Layer ] -> [ State Layer ] -> [ View Layer ]
```

1.  **Data Layer:** Repositories that fetch and cache data (Classes and Resources).
2.  **Coordination Layer:** A Watcher that listens to the Godot Editor and tells Repositories when to refresh.
3.  **State Layer:** The `VREStateManager` that queries Repositories and maintains UI state (Selection, Pagination).
4.  **View Layer:** The UI nodes that observe the State Layer and draw the screen.

---

## 3. Detailed Component Breakdown

### A. The Interfaces (Contracts)

We define base classes that our real and mock repositories will extend. This is the key to testability. By relying on these interfaces, the State Layer doesn't care if it's running in production or in a test environment.

**`core/interfaces/i_global_classes_repository.gd`**
```gdscript
class_name IGlobalClassesRepository
extends RefCounted

signal classes_updated(new_class_list: Array[String])
signal class_renamed(old_name: String, new_name: String)

func get_global_class_list() -> Array[String]: return []
func get_class_path(class_name: String) -> String: return ""
func get_class_properties(class_name: String) -> Array[ResourceProperty]: return []
func get_shared_properties(class_names: Array[String]) -> Array[ResourceProperty]: return []
func get_descendant_classes(class_name: String) -> Array[String]: return []
func refresh() -> void: pass
```

**`core/interfaces/i_resources_repository.gd`**
```gdscript
class_name IResourcesRepository
extends RefCounted

# Emitted when resources for the currently tracked classes change on disk
signal resources_changed(added: Array[Resource], modified: Array[Resource], removed: Array[Resource])
signal resources_replaced(all_resources: Array[Resource])

func get_resources() -> Array[Resource]: return []
func track_classes(class_names: Array[String]) -> void: pass
func save_resource(resource: Resource) -> void: pass
func delete_resource(resource: Resource) -> void: pass
func refresh() -> void: pass
```

### B. The Implementations (Data Layer)

These classes do the heavy lifting of interacting with Godot's file system and the custom scanner.

**`core/repositories/global_classes_repository.gd`**
*   **Implements:** `IGlobalClassesRepository`
*   **Dependencies:** `ProjectScanner` (static utility)
*   **Role:** Caches `global_class_map`, `global_class_to_path_map`, `global_class_to_parent_map`. When `refresh()` is called, it asks `ProjectScanner` to rebuild these maps. It diffs the old and new lists to emit `classes_updated` or `class_renamed`.

**`core/repositories/resources_repository.gd`**
*   **Implements:** `IResourcesRepository`
*   **Dependencies:** `ProjectScanner`
*   **Role:** Maintains `_tracked_classes` and an array of `_cached_resources` (and their mtimes). When `track_classes()` is called, it loads all matching `.tres` files and emits `resources_replaced`. When `refresh()` is called, it scans the disk for changes within the `_tracked_classes`, diffs the mtimes, updates its cache, and emits the granular `resources_changed(added, modified, removed)`.

### C. The Coordinator (Solving the Pending Issue)

This solves your specific problem regarding `_classes_update_pending`. By lifting the `EditorFileSystem` connection out of the State Manager, we centralize the debouncing logic.

**`core/services/editor_filesystem_watcher.gd`**
*   **Extends:** `Node` (Must be in the SceneTree to use Timers and connect to `EditorFileSystem`).
*   **Dependencies:** `IGlobalClassesRepository`, `IResourcesRepository`.
*   **Role:** The *only* class that connects to `EditorFileSystem`. It holds the `DebounceTimer` and the `_classes_update_pending` logic.

```gdscript
# Pseudocode logic for Watcher
func _on_script_classes_updated():
    _classes_update_pending = true
    debounce_timer.start(_handle_classes_updated)

func _on_filesystem_changed():
    if _classes_update_pending: return # Block redundant resource scans
    debounce_timer.start(_handle_fs_changed)

func _handle_classes_updated():
    _classes_update_pending = false
    classes_repo.refresh()
    # Depending on what changed, we might also tell resources_repo to refresh

func _handle_fs_changed():
    resources_repo.refresh()
```

### D. The Application State (State Layer)

**`core/state_manager.gd`** (VREStateManager)
*   **Extends:** `RefCounted` (No longer needs to be a Node! It doesn't need the SceneTree, making it perfectly testable).
*   **Dependencies:** `IGlobalClassesRepository`, `IResourcesRepository`.
*   **State Held:**
    *   `current_class_name: String`
    *   `include_subclasses: bool`
    *   `selected_resources: Array[Resource]`
    *   `current_page: int`
*   **Role:**
    1.  Receives UI intents (e.g., `set_current_class("Enemy")`).
    2.  Asks `ClassesRepo` for subclasses.
    3.  Tells `ResourcesRepo` to `track_classes(["Enemy", "BossEnemy"])`.
    4.  Listens to `ResourcesRepo.resources_replaced` -> Slices the array for `current_page` -> Emits UI signal `page_replaced(page_resources, properties)`.
    5.  Listens to `ResourcesRepo.resources_changed(added, modified, removed)` -> Checks which of these belong to the `current_page` -> Emits granular UI signals `page_resources_added()`, `page_resources_modified()`, etc.
    6.  Handles all Shift/Ctrl click math for `selected_resources`.

## 4. Initialization & Injection Flow

In your `visual_resources_editor_plugin.gd` or `visual_resources_editor_toolbar.gd`, you wire everything together before showing the window:

```gdscript
func _launch_editor():
    # 1. Instantiate the real repositories
    var classes_repo = GlobalClassesRepository.new()
    var resources_repo = ResourcesRepository.new()

    # 2. Instantiate and add the Watcher to the tree
    var watcher = EditorFileSystemWatcher.new(classes_repo, resources_repo)
    EditorInterface.get_base_control().add_child(watcher) # Or a dedicated plugin hidden node

    # 3. Instantiate State Manager (pure logic, no tree required)
    var state_manager = VREStateManager.new(classes_repo, resources_repo)

    # 4. Instantiate Window and Inject State
    var window = preload("uid://.../visual_resources_editor_window.tscn").instantiate()
    window.setup(state_manager)
    EditorInterface.get_editor_main_screen().add_child(window)
```

## 5. Detailed Testing Example

Because `VREStateManager` is now a `RefCounted` object that takes Interfaces, testing is incredibly fast and completely isolated from the Godot Editor. You do not need the SceneTree to test your business logic.

**`tests/test_state_manager.gd`**
```gdscript
extends "res://addons/gut/test.gd" # Example using GUT framework

# 1. Create Mocks
class DummyClassesRepo extends IGlobalClassesRepository:
    var _subclasses = {"Enemy": ["Enemy", "BossEnemy"]}
    func get_descendant_classes(cls): return _subclasses.get(cls, [cls])
    func get_shared_properties(cls_arr): return []

class DummyResourcesRepo extends IResourcesRepository:
    var _resources = []
    func get_resources(): return _resources
    func track_classes(classes):
        # Simulate loading 105 resources immediately without hitting disk
        _resources.clear()
        for i in 105:
            var r = Resource.new()
            r.resource_name = "Res_%d" % i
            _resources.append(r)
        resources_replaced.emit(_resources)

# 2. Write the Test
func test_pagination_math():
    var classes = DummyClassesRepo.new()
    var resources = DummyResourcesRepo.new()
    var state = VREStateManager.new(classes, resources)
    
    state.set_current_class("Enemy")
    
    # Page 0 should have 50 items (assuming PAGE_SIZE = 50 in state manager)
    assert_eq(state.get_current_page_resources().size(), 50)
    
    state.next_page() # Go to Page 1
    assert_eq(state.get_current_page_resources().size(), 50)
    
    state.next_page() # Go to Page 2
    assert_eq(state.get_current_page_resources().size(), 5) # The remaining 5
    
func test_shift_selection():
    var classes = DummyClassesRepo.new()
    var resources = DummyResourcesRepo.new()
    var state = VREStateManager.new(classes, resources)
    
    state.set_current_class("Enemy")
    var page_res = state.get_current_page_resources()
    
    # Click first item
    state.set_selected_resources(page_res[0], false, false)
    assert_eq(state.selected_resources.size(), 1)
    
    # Shift-click 5th item
    state.set_selected_resources(page_res[4], false, true)
    assert_eq(state.selected_resources.size(), 5) # 0, 1, 2, 3, 4 selected
```

## 6. Migration Steps

1.  **Extract Interfaces:** Create `core/interfaces/i_global_classes_repository.gd` and `core/interfaces/i_resources_repository.gd`.
2.  **Extract Repositories:** Move the map building logic from `state_manager.gd` to `core/repositories/global_classes_repository.gd`. Move the resource scanning/mtime diffing logic to `core/repositories/resources_repository.gd`.
3.  **Create Watcher:** Extract the `EditorFileSystem` signal connections and `DebounceTimer` logic into `core/services/editor_filesystem_watcher.gd`.
4.  **Refactor State Manager:** Strip `VREStateManager` down to just `_current_class`, `_current_page`, `selected_resources`, and the logic that filters the repository data for the current page. Change it from `extends Node` to `extends RefCounted` (or keep as `Node` if you prefer, but removing `Node` proves it's decoupled).
5.  **Update UI Setup:** Modify the window instantiation to accept the newly injected `VREStateManager`.
