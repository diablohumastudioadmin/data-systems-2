# VRE Injection Refactor Proposal

This proposal is based on re-reading the current VRE code after the internal split described in `docs/FIXES.md` item 1, with special attention to `docs/TODOS.md` item 2 and item 7.

## Short version

The next refactor should **not** jump straight to strict MVVM.

The best path is:

1. Keep `VREStateManager` as the top-level coordinator.
2. Split the remaining "current browse context" out of `VREStateManager` into one more focused manager.
3. Inject **typed dependencies per component** from `ui/visual_resources_editor_window.gd`.
4. Use a few tiny action/facade objects only where raw managers are still awkward.

That gives us the benefit of TODO item 2 without paying the full cost of TODO item 7.

## What the code says today

The internal split is real and useful:

- `core/state_manager.gd` already delegates to `ClassRegistry`, `ResourceRepository`, `SelectionManager`, `PaginationManager`, and `EditorFileSystemListener`.
- `VREStateManager` is much smaller than before and mostly coordinates signals and refresh flows.

But the UI still depends on the full coordinator everywhere:

- `ui/visual_resources_editor_window.gd` injects `_state` into `ClassSelector`, `SubclassFilter`, `ResourceList`, `Toolbar`, `BulkEditor`, `PaginationBar`, `StatusLabel`, and `Dialogs`.
- `ui/resource_list/resource_row.gd`, `ui/toolbar/toolbar.gd`, `ui/class_selector/class_selector.gd`, `ui/pagination_bar/pagination_bar.gd`, `ui/dialogs/save_resource_dialog.gd`, and `core/bulk_editor.gd` all still call methods on `VREStateManager` directly.

So TODO item 2 is still correct: the code solved the internal god-object problem, but **not** the UI dependency-surface problem.

## The real blocker

The main reason narrow injection is still hard is that `VREStateManager` still owns the current browsing context:

- `_current_class_name`
- `_include_subclasses`
- `_current_included_class_names`
- `current_class_script`
- `current_class_property_list`
- `current_included_class_property_lists`
- `current_shared_property_list`

Those values are not generic repository state and not pure class-registry state either. They are the "what is the user currently browsing/editing?" session.

As long as that session data stays inside `VREStateManager`, components like `ClassSelector`, `SaveResourceDialog`, and `BulkEditor` will keep wanting the whole coordinator.

## Recommended solution

Add one more focused manager:

`core/browse_session.gd`

Suggested responsibilities:

- own `current_class_name`
- own `include_subclasses`
- compute and cache `current_included_class_names`
- compute and cache `current_class_script`
- compute and cache `current_class_property_list`
- compute and cache `current_included_class_property_lists`
- compute and cache `current_shared_property_list`
- emit small, explicit signals when the browse context changes

In other words:

- `ClassRegistry` remains "what classes exist in the project?"
- `BrowseSession` becomes "what class context is the user viewing right now?"
- `ResourceRepository` remains "what resources are loaded for that context?"
- `SelectionManager` remains "what resources are selected?"
- `PaginationManager` remains "what page is visible?"
- `VREStateManager` becomes mostly orchestration glue between those pieces

This is the smallest extra split that makes the injection refactor feel natural instead of forced.

## Why this is better than strict MVVM

TODO item 7 is directionally correct, but full MVVM is too expensive for this plugin right now.

I do **not** recommend introducing a full `ResourceItemViewModel`, `ClassSelectorViewModel`, `ToolbarViewModel`, etc.

Instead:

- keep domain objects (`Resource`, `ResourceProperty`) in the UI where that is already working well
- narrow dependencies by injecting focused managers/services
- only add small presenter-like seams where a widget truly needs cross-manager coordination

That gives us most of the testability and clarity benefit without rewriting the whole UI architecture.

## Proposed dependency map

### 1. Easy wins: direct typed injection

These components can stop receiving `VREStateManager` almost immediately.

`ui/subclass_filter/subclass_filter.gd`
- inject `browse_session: BrowseSession`
- call `browse_session.set_include_subclasses(pressed)`

`ui/class_selector/class_selector.gd`
- inject `class_registry: ClassRegistry`
- inject `browse_session: BrowseSession`
- listen to class-list changes from `ClassRegistry`
- listen to current-class rename/current-class change from `BrowseSession`
- call `browse_session.set_current_class(name)`

`ui/pagination_bar/pagination_bar.gd`
- inject `pagination: PaginationManager`
- inject `page_commands: PageCommands`

`PageCommands` can be a tiny wrapper with:
- `next_page()`
- `prev_page()`

This avoids giving `PaginationBar` the full coordinator just because `PaginationManager.next()` currently needs the full resource array.

`ui/status_label.gd`
- inject `selection: SelectionManager`
- inject `page_feed: ResourcePageFeed`

`ResourcePageFeed` should expose only:
- `resources_replaced`
- `resources_added`
- `resources_removed`

This is much smaller than the whole coordinator and matches what the label actually consumes.

### 2. Medium complexity: small action services

Some controls mostly need commands, not state.

`ui/toolbar/toolbar.gd`
- inject `selection: SelectionManager`
- inject `toolbar_actions: ToolbarActions`

`ToolbarActions` should expose only:
- `request_create_new_resource()`
- `request_delete_selected_resources(paths: Array[String])`
- `refresh_resource_list_values()`

`ui/resource_list/resource_row.gd`
- inject `selection_actions: SelectionActions`
- inject `delete_actions: DeleteActions`

`SelectionActions`:
- `set_selected_resources(resource, ctrl_held, shift_held)`

`DeleteActions`:
- `request_delete_selected_resources(paths)`

This makes `ResourceRow` honest about what it really does.

### 3. Complex widgets: one narrow context each

These are the places where a tiny facade is justified.

`ui/resource_list/resource_list.gd`
- inject `page_feed: ResourcePageFeed`
- inject `selection: SelectionManager`
- inject `row_actions: ResourceRowActions`

`ResourcePageFeed` should own the page-level signals currently forwarded by `VREStateManager`:
- `resources_replaced(resources, props)`
- `resources_added(resources)`
- `resources_modified(resources)`
- `resources_removed(resources)`
- `resources_edited(resources)`

The list should not know about create/delete/current class at all.

`core/bulk_editor.gd`
- inject `selection: SelectionManager`
- inject `browse_session: BrowseSession`
- inject `bulk_edit_service: BulkEditService`
- inject `error_bus: ErrorBus`

`BulkEditService` should expose:
- `save_property_to_resources(resources, property, value) -> Array[Resource]`

This also lines up nicely with TODO item 1, because the save path can move out of the widget at the same time.

`ui/dialogs/save_resource_dialog.gd`
- inject `class_registry: ClassRegistry`
- inject `browse_session: BrowseSession`
- inject `create_requests: CreateResourceRequests`
- inject `error_bus: ErrorBus`

This dialog needs the current class context, not the whole coordinator.

`ui/dialogs/confirm_delete_dialog.gd`
- inject `delete_requests: DeleteRequests`
- inject `error_bus: ErrorBus`

`ui/dialogs/error_dialog.gd`
- inject `error_bus: ErrorBus`

## Concrete new helper types

I would keep this small. Something like:

- `core/browse_session.gd`
- `core/resource_save_service.gd`
- `ui/facades/resource_page_feed.gd`
- `ui/facades/toolbar_actions.gd`
- `ui/facades/page_commands.gd`
- `ui/facades/error_bus.gd`

Important rule:

These helpers should be **thin adapters over existing managers**, not new sources of truth.

If a helper starts caching its own parallel state, we are rebuilding the god object in another shape.

## Recommended phases

### Phase 1: Introduce `BrowseSession`

Do this first.

Move the current browse/session fields out of `VREStateManager` and let the coordinator ask `BrowseSession` for:

- current class name
- included classes
- property caches
- current class script

This one step will make the later UI split much cleaner.

### Phase 2: Centralize saving

Do TODO item 1 while touching `BulkEditor`.

Recommended version:

- add `save_resources()` to `ResourceRepository` or a small `ResourceSaveService`
- return saved resources/paths
- update mtimes in one place
- have `BulkEditor` stop calling `ResourceSaver.save()` directly

This is worth doing before narrowing `BulkEditor` injection because it removes one of its biggest coordinator dependencies.

### Phase 3: Replace whole-state injection in easy widgets

Refactor these first:

- `SubclassFilter`
- `ClassSelector`
- `PaginationBar`
- `Toolbar`
- `ErrorDialog`

These are low-risk and will validate the new property-injection pattern quickly.

### Phase 4: Refactor the complex widgets

Then move:

- `ResourceList`
- `ResourceRow`
- `SaveResourceDialog`
- `ConfirmDeleteDialog`
- `BulkEditor`
- `StatusLabel`

These should use the small facades described above.

## What I would not do

I would not do these in this refactor:

- full MVVM for every control
- replacing `%UniqueName` with a large registration system
- moving every signal into a brand-new event bus
- rewriting rows to avoid `Resource` entirely

Those changes add conceptual weight without clearly improving the plugin enough right now.

## Final recommendation

If we want the smallest good solution, the target should be:

- one more internal split: `BrowseSession`
- one save abstraction for bulk edits and resaves
- typed property injection from the window
- a few tiny facades for widgets that genuinely need cross-manager behavior

That keeps the architecture consistent with FIXES item 1, fully addresses TODO item 2, and takes only the useful subset of TODO item 7 instead of the whole MVVM rewrite.
