# VRE Refactor: Narrow State Manager Injection

**Author:** Claude  
**Status:** Proposal  
**Covers:** TODOS #2 (Narrow Injection), TODOS #7 assessment (Strict MVVM)

---

## Motivation

After FIXES #1 (God-Object split), `VREStateManager` delegates to 5 sub-managers but every UI component still receives the full coordinator. `PaginationBar` only needs prev/next + a page signal, yet it has access to delete files, scan the filesystem, and emit errors. This makes dependency surfaces opaque and blocks independent testing.

---

## Component Dependency Map

Full audit of what each component **actually uses** from `state_manager`:

| Component | Signals listened | Properties read | Methods called |
|---|---|---|---|
| **ResourceRow** | -- | -- | `set_selected_resources()`, `request_delete_selected_resources()` |
| **SubclassFilter** | -- | -- | `set_include_subclasses()` |
| **PaginationBar** | `pagination_changed` | -- | `prev_page()`, `next_page()` |
| **Toolbar** | `selection_changed` | `_selected_paths` | `request_create_new_resouce()`, `request_delete_selected_resources()`, `refresh_resource_list_values()` |
| **ClassSelector** | `project_classes_changed`, `current_class_renamed` | `global_class_name_list` | `set_current_class()` |
| **StatusLabel** | `resources_replaced/added/removed`, `selection_changed` | `selected_resources` | -- |
| **ResourceList** | `resources_replaced/added/modified/removed`, `selection_changed`, `resources_edited` | `selected_resources` | passes state_manager to rows |
| **BulkEditor** | `selection_changed` | `selected_resources`, `current_included_class_property_lists`, `current_class_property_list`, `current_class_script` | `report_error()`, `notify_resources_edited()` |
| **ConfirmDeleteDialog** | `delete_selected_requested` | -- | `report_error()` |
| **SaveResourceDialog** | `create_new_resource_requested` | `current_class_name`, `global_class_map` | `report_error()` |
| **ErrorDialog** | `error_occurred` | -- | -- |

---

## Signal Origin Analysis

Key to deciding what can be narrowed: where does each signal **originate**?

| Coordinator signal | Origin | Re-emit or enriched? |
|---|---|---|
| `selection_changed` | `SelectionManager.selection_changed` | Direct re-emit (line 73) |
| `pagination_changed` | `PaginationManager.pagination_changed` | Direct re-emit (line 76) |
| `resources_replaced` | Coordinator `_on_page_replaced()` | **Enriched** -- adds `current_shared_property_list` |
| `resources_added/modified/removed` | Coordinator `_on_page_delta()` | **Enriched** -- page-sliced, not raw repo data |
| `project_classes_changed` | Coordinator `_on_classes_changed()` | **Enriched** -- fires after orphan resave |
| `current_class_renamed` | Coordinator only | **Coordinator-level** -- no sub-manager equivalent |
| `resources_edited` | Coordinator `notify_resources_edited()` | Pass-through (external trigger) |
| `error_occurred` | Coordinator `report_error()` | Pass-through (external trigger) |
| `delete_selected_requested` | Coordinator `request_delete_selected_resources()` | Pass-through (external trigger) |
| `create_new_resource_requested` | Coordinator `request_create_new_resouce()` | Pass-through (external trigger) |

**Components that listen ONLY to direct re-emits or call methods** can be narrowed to sub-managers + callables. Components that depend on **enriched/coordinator-level signals** cannot.

---

## Phase 1: Clean Targets (Callables Only)

### Change 1.1: Make sub-managers public on VREStateManager

**File:** `core/state_manager.gd`

Rename all 5 sub-manager properties to drop the underscore prefix:

| Current | New |
|---|---|
| `_class_registry` | `class_registry` |
| `_resource_repo` | `resource_repo` |
| `_selection` | `selection` |
| `_pagination` | `pagination` |
| `_fs_listener` | `fs_listener` |

Also rename `_selected_paths` to `selected_paths` -- Toolbar reads it at `toolbar.gd:31` which violates private naming.

**File:** `ui/toolbar/toolbar.gd:31` -- update `state_manager._selected_paths` to `state_manager.selected_paths`

Foundation for Phase 2. No external files reference sub-managers yet, so this is a safe internal rename.

### Change 1.2: Narrow ResourceRow -- two Callables

**File:** `ui/resource_list/resource_row.gd`

Replace:
```gdscript
var state_manager: VREStateManager = null
```
With:
```gdscript
## Callable(resource: Resource, ctrl_held: bool, shift_held: bool) -> void
var on_selected: Callable
## Callable(paths: Array[String]) -> void
var on_delete_requested: Callable
```

Update methods:
```gdscript
func _on_pressed() -> void:
    var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
    var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
    on_selected.call(resource, ctrl_held, shift_held)

func _on_delete_pressed() -> void:
    on_delete_requested.call([resource.resource_path])
```

**File:** `ui/resource_list/resource_list.gd:104`

Replace `row.state_manager = state_manager` with:
```gdscript
row.on_selected = state_manager.set_selected_resources
row.on_delete_requested = state_manager.request_delete_selected_resources
```

GDScript method references are native Callables. No guard or setter needed -- callables are set before `add_child()`.

### Change 1.3: Narrow SubclassFilter -- one Callable

**File:** `ui/subclass_filter/subclass_filter.gd`

Replace:
```gdscript
var state_manager: VREStateManager = null

func _on_include_subclasses_check_toggled(pressed: bool) -> void:
    %SubclassWarningLabel.visible = pressed
    if state_manager:
        state_manager.set_include_subclasses(pressed)
```
With:
```gdscript
## Callable(value: bool) -> void
var on_include_subclasses_changed: Callable

func _on_include_subclasses_check_toggled(pressed: bool) -> void:
    %SubclassWarningLabel.visible = pressed
    if on_include_subclasses_changed:
        on_include_subclasses_changed.call(pressed)
```

**File:** `ui/visual_resources_editor_window.gd:13`

Replace `%SubclassFilter.state_manager = _state` with:
```gdscript
%SubclassFilter.on_include_subclasses_changed = _state.set_include_subclasses
```

### Change 1.4: Fix ErrorDialog wiring bug

**File:** `ui/dialogs/dialogs.gd`

`Dialogs._connect_state()` sets `state_manager` on `%ConfirmDeleteDialog` and `%SaveResourceDialog` but **not** `%ErrorDialog`. So `state_manager.error_occurred` is never connected to `ErrorDialog.show_error()` -- all `report_error()` calls from BulkEditor, SaveResourceDialog, and ConfirmDeleteDialog are silently lost.

Add to `_connect_state()`:
```gdscript
%ErrorDialog.state_manager = state_manager
```

---

## Phase 2: Sub-Manager Injection

### Change 2.1: Narrow PaginationBar -- PaginationManager + 2 Callables

`pagination_changed` is a direct re-emit from `PaginationManager.pagination_changed`. `prev_page()` and `next_page()` are coordinator methods because they pass `_resource_repo.current_class_resources` into PaginationManager -- they can't be called on PaginationManager directly.

**File:** `ui/pagination_bar/pagination_bar.gd`

Replace:
```gdscript
var state_manager: VREStateManager = null:
    set(value):
        state_manager = value
        if is_node_ready():
            _connect_state()

func _connect_state() -> void:
    %PrevBtn.pressed.connect(state_manager.prev_page)
    %NextBtn.pressed.connect(state_manager.next_page)
    state_manager.pagination_changed.connect(_on_pagination_changed)
```
With:
```gdscript
var pagination: PaginationManager = null:
    set(value):
        pagination = value
        if is_node_ready():
            _connect_state()

## Callable() -> void
var on_prev: Callable
## Callable() -> void
var on_next: Callable

func _connect_state() -> void:
    %PrevBtn.pressed.connect(on_prev)
    %NextBtn.pressed.connect(on_next)
    pagination.pagination_changed.connect(_on_pagination_changed)
```

**File:** `ui/visual_resources_editor_window.gd`

Replace `%PaginationBar.state_manager = _state` with:
```gdscript
%PaginationBar.pagination = _state.pagination
%PaginationBar.on_prev = _state.prev_page
%PaginationBar.on_next = _state.next_page
```

### Change 2.2: Narrow Toolbar -- SelectionManager + 3 Callables

`selection_changed` is a direct re-emit from `SelectionManager.selection_changed`. The 3 coordinator methods are simple signal-emitters or orchestration calls.

**File:** `ui/toolbar/toolbar.gd`

Replace:
```gdscript
var state_manager: VREStateManager = null:
    set(value):
        state_manager = value
        if is_node_ready():
            _connect_state()

func _connect_state() -> void:
    state_manager.selection_changed.connect(update_selection)

func _on_delete_selected_pressed() -> void:
    state_manager.request_delete_selected_resources(state_manager.selected_paths)

func _on_create_btn_pressed() -> void:
    state_manager.request_create_new_resouce()

func _on_refresh_btn_pressed() -> void:
    state_manager.refresh_resource_list_values()
```
With:
```gdscript
var selection: SelectionManager = null:
    set(value):
        selection = value
        if is_node_ready():
            _connect_state()

## Callable() -> void
var on_create: Callable
## Callable(paths: Array[String]) -> void
var on_delete_selected: Callable
## Callable() -> void
var on_refresh: Callable

func _connect_state() -> void:
    selection.selection_changed.connect(update_selection)

func _on_delete_selected_pressed() -> void:
    on_delete_selected.call(selection.get_paths())

func _on_create_btn_pressed() -> void:
    on_create.call()

func _on_refresh_btn_pressed() -> void:
    on_refresh.call()
```

**File:** `ui/visual_resources_editor_window.gd`

Replace `%Toolbar.state_manager = _state` with:
```gdscript
%Toolbar.selection = _state.selection
%Toolbar.on_create = _state.request_create_new_resouce
%Toolbar.on_delete_selected = _state.request_delete_selected_resources
%Toolbar.on_refresh = _state.refresh_resource_list_values
```

---

## Narrowing Boundary: Why the Remaining 7 Components Stay on `state_manager`

| Component | Blocker |
|---|---|
| **ClassSelector** | Needs `project_classes_changed` (enriched -- fires after orphan resave, not raw ClassRegistry signal) + `current_class_renamed` (coordinator-only signal). ClassRegistry alone is insufficient. |
| **StatusLabel** | Needs `resources_replaced/added/removed` -- these are page-sliced coordinator signals produced by PaginationManager + ResourceRepository orchestration. No single sub-manager emits them. |
| **ResourceList** | 6 coordinator signals (all page-sliced) + `selected_resources`. Heaviest signal consumer. |
| **BulkEditor** | Reads `current_included_class_property_lists`, `current_class_property_list`, `current_class_script` -- coordinator-computed state that spans ClassRegistry scan results and current UI context. No sub-manager owns this. |
| **ConfirmDeleteDialog** | Needs `delete_selected_requested` (coordinator pass-through signal) + `report_error()`. |
| **SaveResourceDialog** | Needs `create_new_resource_requested` + `current_class_name` + `global_class_map` + `report_error()`. Spans ClassRegistry data + coordinator state + error channel. |
| **ErrorDialog** | Only needs `error_occurred` -- could be narrowed to a single callable, but it's already behind the Dialogs pass-through and the fix in Change 1.4 handles wiring. Low value. |

**Common pattern in all blockers:** The coordinator **enriches** sub-manager signals before re-emitting them (adds `current_shared_property_list`, page-slices resources, fires after orphan resave). Components that depend on these enriched signals can't bypass the coordinator without duplicating the enrichment logic.

---

## TODOS #7: Strict MVVM Assessment

### What MVVM Would Change

To narrow the remaining 7 components, you'd introduce **ViewModel objects** -- lightweight typed RefCounted classes that encapsulate exactly what each component needs, with their own signals:

```
Coordinator (state_manager)
    ├── ClassSelectorViewModel    → ClassSelector
    │     .class_list: Array[String]
    │     .classes_changed signal
    │     .class_renamed signal
    │     .select_class(name) method
    │
    ├── ResourceListViewModel     → ResourceList
    │     .page_resources: Array[ResourceRowData]
    │     .resources_replaced signal
    │     .resources_delta signal
    │     .selection signal
    │
    ├── BulkEditorViewModel       → BulkEditor
    │     .selected: Array[Resource]
    │     .property_list: Array[ResourceProperty]
    │     .script: GDScript
    │     .selection_changed signal
    │     .save(res) / report_error(msg)
    │
    └── StatusViewModel           → StatusLabel
          .visible_count: int
          .selected_count: int
          .counts_changed signal
```

The coordinator would populate these ViewModels and emit their signals. Components would only know about their ViewModel type -- zero knowledge of VREStateManager, sub-managers, or domain orchestration.

### Why Defer MVVM

1. **Scale doesn't justify it yet.** The plugin has 11 components. The coordinator has 12 signals. Introducing 4-5 ViewModel classes adds ~200 LOC of glue code and a new abstraction layer. The testability gain is real but the plugin is small enough that integration testing covers it.

2. **No compile-time safety.** GDScript has no interfaces. ViewModels would be typed classes, but a component could still access anything on a ViewModel that wasn't intended. The narrowing is documentation, not enforcement.

3. **Risk of premature abstraction.** The VRE UI is still evolving (TODOS #1 save centralization, #4 async scanning). ViewModel contracts may shift as coordinator logic changes. Better to stabilize the coordinator first.

4. **Callable narrowing covers the high-value targets.** ResourceRow (most-instantiated), SubclassFilter, PaginationBar, and Toolbar are the components where a misplaced `state_manager.` call is most likely. Phase 1+2 covers all of them without ViewModel overhead.

### When to Revisit MVVM

- If the plugin grows to 20+ components or the coordinator gets 20+ signals
- If unit testing becomes a priority (mocking a ViewModel is trivial vs. mocking VREStateManager)
- If multiple developers work on the UI simultaneously (ViewModel contracts reduce merge conflicts)

---

## Cross-Analysis: Codex Proposal (`refactor_injection_codex.md`)

Codex proposes a different strategy for the same problem. This section compares the two approaches honestly -- where Codex is right, where it over-engineers, and what this proposal should absorb.

### Codex Strategy Summary

Codex introduces **~6 new types** to achieve full narrowing of all 11 components:

- `BrowseSession` -- extracts current-browsing-context state (`current_class_name`, `include_subclasses`, property caches) from VREStateManager into a new manager
- `ResourcePageFeed` -- facade owning page-level resource signals
- `ToolbarActions` -- facade wrapping 3 coordinator methods
- `PageCommands` -- facade wrapping `prev_page()` / `next_page()`
- `ErrorBus` -- single signal emitter for error reporting
- `ResourceSaveService` / `BulkEditService` -- save abstraction

Phases: BrowseSession extraction first, then save centralization (TODOS #1), then easy widgets, then complex widgets.

### Where Codex Is Right

**1. BrowseSession is the key insight this proposal lacks.**

This proposal correctly identifies that 7 components are blocked by enriched/coordinator-level signals and says "defer to MVVM." Codex identifies **why** they're blocked: `VREStateManager` owns the browsing context (current class, included classes, property caches) which is neither ClassRegistry state nor ResourceRepository state -- it's session state.

Extracting `BrowseSession` would unblock `ClassSelector`, `SaveResourceDialog`, and `BulkEditor` without full MVVM. Those three components primarily need browsing-context reads (`current_class_name`, `current_class_script`, property lists) plus error reporting. With `BrowseSession` as a real manager, they can receive `BrowseSession` instead of the whole coordinator.

This is a genuine middle ground between "stay on state_manager" (this proposal) and "full MVVM" (deferred). **This proposal should absorb this idea as a Phase 3.**

**2. ErrorBus is a reasonable pattern.**

A dedicated error signal emitter would let `ConfirmDeleteDialog`, `SaveResourceDialog`, and `ErrorDialog` receive a single-purpose object instead of the full coordinator. The current bug (Change 1.4: ErrorDialog never wired) is evidence that error routing through `state_manager` is fragile.

**3. Phasing through save centralization.**

Codex correctly links this refactor to TODOS #1 (save centralization). Narrowing `BulkEditor` is much cleaner after saves move out of the widget. This proposal treats TODOS #1 and #2 as independent; Codex recognizes they compound.

### Where Codex Over-Engineers

**1. Facade proliferation for 1-3 method surfaces.**

`ToolbarActions` (3 methods), `PageCommands` (2 methods), `SelectionActions` (1 method), `DeleteActions` (1 method) -- these are Callables with extra steps. GDScript method references are native Callables:

```gdscript
# Codex: introduce ToolbarActions class with 3 methods
toolbar.toolbar_actions = ToolbarActions.new(state_manager)

# This proposal: pass 3 Callables directly
toolbar.on_create = _state.request_create_new_resouce
toolbar.on_delete_selected = _state.request_delete_selected_resources
toolbar.on_refresh = _state.refresh_resource_list_values
```

The Callable approach achieves identical narrowing without introducing a class. For surfaces of 1-3 methods, Callables are strictly better: no file, no type, same decoupling. A facade class is only justified when the surface grows large enough that individual Callables become unwieldy (5+ methods) or when the facade needs its own state.

**2. ResourcePageFeed doesn't solve the enrichment problem.**

Codex says `ResourcePageFeed` should own page-level signals (`resources_replaced`, `resources_added`, etc.). But these signals are **produced by** coordinator orchestration -- `_on_page_replaced()` and `_on_page_delta()` in `state_manager.gd` combine PaginationManager slicing with ResourceRepository data. Moving them to a facade means either:

- The facade just **re-emits** what the coordinator produces -- adding a layer of indirection with no narrowing benefit (the coordinator still produces the data, the facade just forwards it)
- The facade **computes** them itself -- duplicating coordinator logic, violating Codex's own rule that "helpers should be thin adapters, not new sources of truth"

`StatusLabel` and `ResourceList` depend on these page-sliced signals. `ResourcePageFeed` cannot meaningfully narrow their dependency without duplicating the coordinator's orchestration. This is the same conclusion this proposal reached -- these components genuinely depend on coordinator-level work.

**3. BrowseSession computation chain is non-trivial.**

The cached properties in VREStateManager (`current_class_script`, `current_class_property_list`, `current_shared_property_list`) depend on **both** ClassRegistry data and ResourceRepository data. Moving them to `BrowseSession` means `BrowseSession` needs references to both managers and must subscribe to both managers' signals to recompute caches. This creates a new coordination point rather than eliminating one.

It's still worth doing (the browsing context is a legitimate domain concept), but it's not the "smallest extra split" Codex claims -- it requires careful signal rewiring in the coordinator.

**4. Component count doesn't justify 6 new types.**

The plugin has 11 UI components. Adding 6 facade/helper types (even thin ones) nearly doubles the type count of the architecture. Each new type is a file, a `class_name`, a constructor, and a wiring point in the window. For a plugin this size, the cognitive overhead of "which facade does this method live on?" can exceed the original problem of "this component has access to methods it doesn't use."

### What Codex Missed

**1. The ErrorDialog wiring bug.**

`Dialogs._connect_state()` sets `state_manager` on `%ConfirmDeleteDialog` and `%SaveResourceDialog` but **never** on `%ErrorDialog`. All `report_error()` calls are silently lost. This is a concrete bug affecting users today, and Codex's proposal doesn't mention it. This proposal's Change 1.4 fixes it.

**2. Signal origin analysis.**

Codex doesn't distinguish between direct re-emits (`selection_changed`, `pagination_changed`) and enriched signals (`resources_replaced`, `project_classes_changed`). This distinction is critical for determining what CAN be narrowed without new abstractions. Without it, Codex assumes facades can absorb all signals, when in practice `ResourcePageFeed` would just be a pass-through.

**3. Implementation specifics.**

Codex describes desired end-state but provides no code snippets, no line references, no exact property changes. This proposal includes concrete GDScript for every change with file:line references. For a refactor touching 10+ files, the devil is in the details.

### Revised Recommendation: Absorb BrowseSession as Phase 3

This proposal should add a Phase 3 that adopts Codex's `BrowseSession` idea:

| Phase | What | Components Narrowed |
|---|---|---|
| **Phase 1** (this proposal) | Callables + public sub-managers + ErrorDialog fix | ResourceRow, SubclassFilter |
| **Phase 2** (this proposal) | Sub-manager + Callables | PaginationBar, Toolbar |
| **Phase 3** (from Codex) | Extract `BrowseSession` from coordinator | ClassSelector, SaveResourceDialog, BulkEditor |
| **Remaining** | Stay on `state_manager` | StatusLabel, ResourceList, ConfirmDeleteDialog |

Phase 3 rationale: `BrowseSession` would hold `current_class_name`, `include_subclasses`, and the computed property caches. `ClassSelector` would receive `ClassRegistry` + `BrowseSession`. `SaveResourceDialog` would receive `BrowseSession` + an error callable. `BulkEditor` would receive `SelectionManager` + `BrowseSession` + error callable.

`StatusLabel`, `ResourceList`, and `ConfirmDeleteDialog` would still need `state_manager` -- their dependency on page-sliced signals and coordinator pass-through signals (`delete_selected_requested`) is not addressed by `BrowseSession`.

This gets us from 4 narrowed components (Phases 1-2) to 7 narrowed components (Phase 3), without the facade proliferation that Codex proposes.

### Summary Table: Approach Comparison

| Dimension | This Proposal (Claude) | Codex Proposal |
|---|---|---|
| **New types introduced** | 0 | ~6 |
| **Components narrowed** | 4 (Phases 1-2) | 11 (all, in theory) |
| **Narrowing mechanism** | Callables + sub-managers | Facades + new managers |
| **BrowseSession extraction** | Not proposed (identified as blocker, deferred) | Core of proposal |
| **ErrorDialog bug** | Found and fixed (Change 1.4) | Not identified |
| **Signal origin analysis** | Full table (direct vs enriched) | Not performed |
| **Code specifics** | Line-level GDScript snippets | Architecture-level only |
| **Risk profile** | Very low (Phase 1-2 are safe renames + callables) | Medium (BrowseSession touches coordinator internals) |
| **Best used as** | Immediate implementation plan | Architectural north star for Phase 3+ |

---

## Implementation Summary

| Phase | Components narrowed | Approach | Effort |
|---|---|---|---|
| **Phase 1** | ResourceRow, SubclassFilter | Callables only | Low |
| **Phase 1** | (foundation) | Make sub-managers public, fix ErrorDialog | Low |
| **Phase 2** | PaginationBar, Toolbar | Sub-manager + callables | Medium |
| **--** | ClassSelector, StatusLabel, ResourceList, BulkEditor, Dialogs (x3) | Stay on `state_manager` | -- |
| **Future** | All remaining | MVVM (ViewModel layer) | High -- defer |

### Implementation Order

1. Change 1.1 (sub-managers public + `selected_paths`) -- one commit
2. Change 1.2 (ResourceRow callables) -- one commit
3. Change 1.3 (SubclassFilter callable) -- one commit
4. Change 1.4 (ErrorDialog bug fix) -- one commit
5. Change 2.1 (PaginationBar) -- one commit
6. Change 2.2 (Toolbar) -- one commit

### Verification

1. Open VRE window, select a class -- rows appear
2. Click a row -- selects (tests `on_selected` callable)
3. Click row delete button -- confirm dialog appears (tests `on_delete_requested` callable)
4. Toggle "Include Subclasses" -- filters/unfilters (tests SubclassFilter callable)
5. Trigger a save error in bulk editor -- error dialog now appears (tests ErrorDialog fix)
6. Toolbar "Delete Selected" -- works (tests `selected_paths` rename)
7. Page navigation -- works (tests PaginationBar narrowing)
8. Toolbar create/refresh -- works (tests Toolbar callables)
