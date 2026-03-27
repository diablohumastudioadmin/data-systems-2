# Visual Resources Editor - Architecture Proposal (Codex)

## Short answer

Yes, your direction is good.

Separating:
- global class metadata
- resource indexing/loading
- UI-facing state

is exactly the right move for both problems you want to solve:

1. `state_manager.gd` is too large because it mixes data access, editor event handling, and UI state.
2. non-scene-tree testing is hard because the current logic depends directly on `Node`, `EditorInterface`, `EditorFileSystem`, and a debounce timer.

The one important change I would make to your idea is this:

**Do not make both repositories listen to `EditorFileSystem` directly.**

Instead, use:
- 2 repositories behind abstract base classes
- 1 tiny editor-only coordinator/bridge that listens to `EditorFileSystem`
- 1 slim `StateManager` that is really the ViewModel

That gives `_classes_update_pending` a natural home, keeps the repositories fakeable, and avoids pushing editor-specific coordination back into the state layer.

---

## Recommendation

I recommend a **MVVM-lite / Presenter-friendly** architecture:

- **Model-ish layer**:
  - `VREProjectScanner` (pure helper)
  - `VREGlobalClassesRepository`
  - `VREResourcesRepository`
- **Editor integration layer**:
  - `VREEditorSyncCoordinator`
- **ViewModel layer**:
  - `VREStateManager` or `VREViewModel`
- **View layer**:
  - existing UI scenes

This is better than strict MVC/VIPER here because:
- the UI already works well as signal-based views
- selection + pagination + filtered current-class state are tightly coupled and should stay together
- Godot editor integration is easier when there is one explicit composition root

So I would not split into:
- `SelectionModel`
- `PaginationState`
- `ClassMetadataScanner`
- `ResourceRepository`

That is too fragmented for this plugin.

I would split by **dependency boundary**, not by tiny responsibility.

---

## What I agree with from your idea

These parts are strong:

- a `global_classes_repository`
- a `resources_repository`
- abstract inheritance for both so tests can inject fakes
- keeping selection and pagination in `state_manager`
- composing everything in the plugin/window and injecting dependencies downward

These parts I would change:

- repositories should not expose static mutable test data
- repositories should not own `EditorFileSystem` subscriptions
- the resources repository should not own "current selected class" state
- the first refactor should not require every UI component to become fully MVVM-aware immediately

---

## Core design principle

Use this rule:

**Repositories own project data.  
The ViewModel owns current query state and UI state.  
The editor bridge owns editor signals and debounce.**

That one rule keeps the split clean.

---

## Proposed architecture

### 1. `VREProjectScanner` (rename from `ProjectClassScanner`)

I agree with renaming, but I would rename it to one of these:

- `VREProjectScanner`
- `ProjectScanner`

I would not use `project_scaner`; that keeps the typo forever.

Responsibilities:

- pure stateless helper methods
- build global class maps
- read script properties
- read `.tres` headers to extract `script_class`
- load resources from paths

Important rule:

- no editor signal connections
- no long-lived mutable state
- no selection/pagination logic

So this file remains a pure utility boundary.

---

### 2. `VREGlobalClassesRepositoryBase`

This is the abstract base for real and fake class repositories.

Suggested type:

- `extends RefCounted`

Why `RefCounted`:

- no scene tree needed
- easy to instantiate in tests
- still supports methods, state, and signals

Suggested responsibilities:

- cache the current project class metadata
- cache `class_to_path`
- cache `class_to_parent`
- cache project resource class names
- cache per-class property lists
- answer class queries

Suggested API:

```gdscript
class_name VREGlobalClassesRepositoryBase
extends RefCounted

signal changed()

func refresh() -> void:
    push_error("Abstract")

func get_global_class_map() -> Array[Dictionary]:
    push_error("Abstract")
    return []

func get_resource_class_names() -> Array[String]:
    push_error("Abstract")
    return []

func has_class(class_name_str: String) -> bool:
    push_error("Abstract")
    return false

func get_script_path(class_name_str: String) -> String:
    push_error("Abstract")
    return ""

func get_script(class_name_str: String) -> GDScript:
    push_error("Abstract")
    return null

func get_descendant_classes(base_class: String, include_base: bool = true) -> Array[String]:
    push_error("Abstract")
    return []

func get_class_properties(class_name_str: String) -> Array[ResourceProperty]:
    push_error("Abstract")
    return []

func get_shared_properties(class_names: Array[String]) -> Array[ResourceProperty]:
    push_error("Abstract")
    return []

func find_class_name_by_script_path(script_path: String) -> String:
    push_error("Abstract")
    return ""
```

Concrete implementation:

- `VREEditorGlobalClassesRepository`

It uses `VREProjectScanner` internally and is the only place that reads `ProjectSettings.get_global_class_list()`.

Important detail:

It should cache properties by class name so the ViewModel never needs to call the scanner directly.

---

### 3. `VREResourcesRepositoryBase`

This is the abstract base for real and fake resource repositories.

Suggested type:

- `extends RefCounted`

Suggested responsibilities:

- maintain the project-wide resource index
- cache resource mtimes
- cache resource objects by path
- map `path -> class_name`
- answer filtered queries by class names
- expose the current project resource snapshot

Important design choice:

I would **not** make this repository own `current_included_classes_resources`.

That belongs in the ViewModel because:
- it depends on current class selection
- it depends on `include_subclasses`
- it is part of the UI query, not the project data itself

So the repository should own the **global index**, and the ViewModel should derive the filtered subset.

Suggested API:

```gdscript
class_name VREResourcesRepositoryBase
extends RefCounted

signal changed()

func refresh() -> void:
    push_error("Abstract")

func get_all_paths() -> Array[String]:
    push_error("Abstract")
    return []

func has_path(path: String) -> bool:
    push_error("Abstract")
    return false

func get_class_name_for_path(path: String) -> String:
    push_error("Abstract")
    return ""

func get_resource(path: String) -> Resource:
    push_error("Abstract")
    return null

func get_resources_for_classes(class_names: Array[String]) -> Array[Resource]:
    push_error("Abstract")
    return []

func get_mtime(path: String) -> int:
    push_error("Abstract")
    return -1
```

Concrete implementation:

- `VREEditorResourcesRepository`

Internal state can look like this:

```gdscript
var _resource_by_path: Dictionary[String, Resource] = {}
var _class_name_by_path: Dictionary[String, String] = {}
var _mtime_by_path: Dictionary[String, int] = {}
var _paths_by_class_name: Dictionary[String, Array[String]] = {}
```

That is enough to support:
- quick filtering by class
- quick mtime-based change detection
- resource reuse on non-modified files

---

### 4. `VREEditorSyncCoordinator`

This is the missing piece in your proposal, and I think it is the key one.

Suggested type:

- `extends Node`

This is the only layer that should know about:

- `EditorInterface`
- `EditorFileSystem`
- debounce timer
- `_classes_update_pending`

Responsibilities:

- connect to `EditorFileSystem.filesystem_changed`
- connect to `EditorFileSystem.script_classes_updated`
- debounce those events
- coordinate refresh order between repositories
- suppress or queue filesystem refreshes while class refresh is in progress

This prevents editor concerns from leaking into repositories or the ViewModel.

#### Why not let each repository listen directly?

Because then:
- both repositories need editor dependencies
- both repositories need debounce logic
- both repositories need to know about `_classes_update_pending`
- tests become much harder again

The coordinator makes this clean.

#### Better replacement for `_classes_update_pending`

Use two flags instead of one:

```gdscript
var _class_update_pending: bool = false
var _filesystem_refresh_queued: bool = false
```

Suggested behavior:

```gdscript
func _on_script_classes_updated() -> void:
    _class_update_pending = true
    %DebounceTimer.start_debouncing(_apply_class_update)


func _on_filesystem_changed() -> void:
    if _class_update_pending:
        _filesystem_refresh_queued = true
        return
    %DebounceTimer.start_debouncing(_apply_filesystem_update)


func _apply_class_update() -> void:
    global_classes_repo.refresh()
    resources_repo.refresh()
    _class_update_pending = false

    if _filesystem_refresh_queued:
        _filesystem_refresh_queued = false
        %DebounceTimer.start_debouncing(_apply_filesystem_update)


func _apply_filesystem_update() -> void:
    resources_repo.refresh()
```

This is better than the current boolean-only approach because it does not silently drop a filesystem refresh that arrived during a class update.

#### Where should orphan resave live?

If you keep the current "resave orphaned resources after class changes" behavior, I would place that side effect here or in a separate file-operations service, not in the ViewModel.

Reason:

- it is an editor/file-system side effect
- it is not UI state
- it depends on previous/new repository snapshots

---

### 5. `VREStateManager` becomes a real ViewModel

You can keep the name `VREStateManager` to reduce churn, but conceptually this becomes the ViewModel.

Suggested type:

- preferred target: `extends RefCounted`
- transitional option: keep `extends Node` for one refactor step, then convert later

If testability is a priority, I strongly prefer `RefCounted`.

Responsibilities:

- own current class selection
- own `include_subclasses`
- derive current included class names from the classes repository
- derive current class script and property lists from the classes repository
- derive current filtered resources from the resources repository
- own selection state
- own pagination state
- compute page slices
- diff previous/current page slices and emit UI-facing signals

This means it should own:

- `_current_class_name`
- `_include_subclasses`
- `_current_included_class_names`
- `current_class_script`
- `current_class_property_list`
- `current_shared_property_list`
- `current_class_resources`
- `selected_resources`
- `_selected_paths`
- `_selected_resources_last_index`
- `_current_page`
- `_current_page_resources`

This means it should no longer own:

- `EditorFileSystem` listeners
- debounce timer
- raw project scan functions
- project-wide class-map building
- project-wide resource indexing

#### ViewModel dependencies

```gdscript
func _init(
    p_global_classes_repo: VREGlobalClassesRepositoryBase,
    p_resources_repo: VREResourcesRepositoryBase
) -> void:
```

The ViewModel listens to:

- `global_classes_repo.changed`
- `resources_repo.changed`

#### Rename detection belongs here

Current-class rename detection should live in the ViewModel, not the repository.

Why:

- rename handling depends on the currently selected class
- the repository should expose facts, not UI decisions

Suggested rule:

- if current class name disappears
- ask repository for the old selected class script path
- find whether another class now maps to that same script path
- if yes, treat as rename and emit `current_class_renamed`
- if no, clear the view

#### Keep the existing UI signal contract if possible

To minimize migration, keep these signals:

- `resources_replaced`
- `resources_added`
- `resources_removed`
- `resources_modified`
- `project_classes_changed`
- `selection_changed`
- `pagination_changed`
- `current_class_renamed`

That lets you refactor internals without rewriting every view immediately.

---

## Composition root

Your instinct here is right.

Create concrete dependencies in one place and inject them downward.

I would use one of these as the composition root:

- `VisualResourcesEditorToolbar.open_visual_editor_window()`
- `VisualResourcesEditorWindow.initialize(...)`

Either is fine.

Suggested flow:

1. create concrete repositories
2. create coordinator with those repositories
3. create ViewModel with repository interfaces
4. create window
5. pass ViewModel to window
6. pass only the ViewModel to UI components
7. add coordinator as a child `Node` somewhere editor-safe

Pseudo-code:

```gdscript
var global_repo: VREGlobalClassesRepositoryBase = VREEditorGlobalClassesRepository.new()
var resources_repo: VREResourcesRepositoryBase = VREEditorResourcesRepository.new()
var view_model: VREStateManager = VREStateManager.new(global_repo, resources_repo)
var sync: VREEditorSyncCoordinator = VREEditorSyncCoordinator.new(global_repo, resources_repo)

window.initialize(view_model, sync)
```

I would **not** pass repositories into UI components.

Views should receive:

- the ViewModel
- maybe a file-operations service if they truly need one

But not raw repositories.

---

## Testing strategy

This architecture directly improves non-scene-tree testing.

### What becomes easy to unit test

With fake repositories, you can test all of this without a scene tree:

- selecting a class resets pagination
- toggling include-subclasses changes the included class set
- shift-selection across pages
- restoring selection after repository changes
- page clamping after deletions
- rename detection
- subclass-property union changes
- incremental current-page diffing

### What still needs editor/integration tests

Only a small layer needs editor integration:

- `VREEditorSyncCoordinator`
- concrete editor repositories that talk to `ProjectSettings` / `FileAccess` / `ResourceLoader`

That is okay.

You do not need everything to be unit tested to get a huge improvement.

### Fake repositories

Use per-test fake instances, not `static` state.

Bad:

- static arrays
- static dictionaries
- test state shared across tests

Good:

```gdscript
class_name FakeGlobalClassesRepository
extends VREGlobalClassesRepositoryBase

var _resource_classes: Array[String] = []
var _class_to_path: Dictionary[String, String] = {}
var _properties_by_class: Dictionary[String, Array[ResourceProperty]] = {}
```

Each test builds its own fake state and emits `changed` manually.

That keeps tests isolated and deterministic.

---

## Proposed folder structure

One reasonable structure:

```text
visual_resources_editor/
├── core/
│   ├── scanners/
│   │   └── vre_project_scanner.gd
│   ├── repositories/
│   │   ├── global_classes_repository_base.gd
│   │   ├── editor_global_classes_repository.gd
│   │   ├── resources_repository_base.gd
│   │   └── editor_resources_repository.gd
│   ├── editor/
│   │   └── editor_sync_coordinator.gd
│   ├── view_models/
│   │   └── vre_state_manager.gd
│   ├── services/
│   │   └── file_operations.gd
│   └── data_models/
│       ├── class_definition.gd
│       ├── resource_property.gd
│       └── resource_record.gd
└── ui/
```

If you want less churn, keep `state_manager.gd` where it is and only add:

- `core/repositories/`
- `core/editor/`

That is also fine.

---

## Suggested migration plan

### Phase 1: Extract repositories without changing the UI contract

Goal:

- keep window and views mostly unchanged
- keep current state-manager signals
- move data and editor concerns out first

Steps:

1. Rename `ProjectClassScanner` to `VREProjectScanner` or `ProjectScanner`.
2. Add repository base classes.
3. Add concrete editor repositories.
4. Move class-map logic and property lookups into the global classes repository.
5. Move resource index / mtime logic into the resources repository.
6. Add `VREEditorSyncCoordinator`.
7. Inject repositories into `VREStateManager`.
8. Remove `EditorFileSystem` subscriptions from `VREStateManager`.

At this point:

- code is already smaller
- testing becomes much easier
- UI can still run with the old signal contract

### Phase 2: Convert `VREStateManager` from `Node` to `RefCounted`

Goal:

- make the ViewModel fully non-scene-tree testable

Steps:

1. remove `%RescanDebounceTimer` dependency from state manager
2. stop relying on being in the scene tree
3. construct it from code and inject it into the window

This is the biggest testability win.

### Phase 3: Optionally let views bind to the ViewModel more directly

Optional only.

You can keep the window as a coordinator if you prefer.

But later you may choose to let:

- `ClassSelector`
- `ResourceList`
- `Toolbar`

receive the ViewModel directly via `initialize(view_model)`.

I would not do this in the first pass.

---

## Suggested boundaries for current code

Here is how I would split the current `state_manager.gd` responsibilities.

### Move to `VREGlobalClassesRepository`

- `_set_maps()`
- `_get_class_script()`
- `_get_current_class_props()` equivalent logic
- descendant-class queries
- per-class property scanning
- shared-property union logic

### Move to `VREResourcesRepository`

- `_scan_class_resources_for_changes()` but generalized to project-wide index refresh
- `_rebuild_current_class_resource_mtimes()` equivalent internal cache logic
- resource loading/reloading by path

### Move to `VREEditorSyncCoordinator`

- `_ready()` editor subscriptions
- `_exit_tree()` disconnections
- `_on_script_classes_updated()`
- `_on_filesystem_changed()`
- debounce orchestration
- `_classes_update_pending`

### Keep in `VREStateManager`

- `set_current_class()`
- `set_include_subclasses()`
- `set_selected_resources()`
- `handle_select_shift()`
- `handle_select_ctrl()`
- `handle_select_no_key()`
- `next_page()`
- `prev_page()`
- `_restore_selection()`
- `_set_current_page()`
- `set_current_page_resources()`
- `_scan_page_resources_for_changes()`
- `_page_count()`
- `_emit_page_data()`
- `_clear_view()`
- current-class rename handling

That is the clean split.

---

## Why this solves your 2 original problems

### Problem 1: `state_manager` is too big

After the split, the ViewModel only owns:

- current filters
- current derived data
- current selection
- current pagination
- UI-facing signals

That is a normal-sized ViewModel.

### Problem 2: testing outside the scene tree is too hard

After the split:

- repositories can be faked
- ViewModel can be instantiated without `Node`
- editor-specific behavior is isolated to one tiny coordinator

That makes unit tests realistic.

---

## Final recommendation

Use:

- **2 repositories**
- **1 editor sync coordinator**
- **1 ViewModel**

Not:

- 2 repositories that both listen directly to editor signals
- 4+ tiny state objects for selection, pagination, filtering, etc.
- static fake repositories

If you want the shortest version of the proposal:

**Your idea is good, but the right architecture is not "repos + state manager only".  
It is "repos + editor bridge + state manager/viewmodel".**

That is the version I would implement.
