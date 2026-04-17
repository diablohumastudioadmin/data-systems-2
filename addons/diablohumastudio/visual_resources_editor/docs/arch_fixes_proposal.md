# VRE Progressive Rearchitecture — Status & Remaining Plan

**Branch:** `claude/epic-heyrovsky`  
**Goal:** Delete `VREModel` god-object. Flat MVVM: Session + Services → VMs directly.

---

## DONE (committed)

| Commit | What |
|--------|------|
| `b33fff4` | **0.1** Typo fix: `request_create_new_resouce` → `request_create_new_resource` |
| `2889d60` | **0.2** Extract `ResourceSorter` static utility from VREModel |
| `ef06a85` | **0.3** Move property scanning into `ClassRegistry.get_properties_for / get_shared_properties` |
| `6bbe2d8` | **1** Selection by path: `selected_resources→selected_paths`, SelectionManager rewritten on strings, `restore()` deleted |

## DONE — Phase 2 (committed as 4 commits: 2f4e7c4, f2cea5c, 1d50269, abacac0)

**Phase 2 — ResourceRepository owns all disk I/O**

- ✅ **2.1** Added: `error_occurred`/`resources_saved` signals, `get_by_path`, `create`, `delete`, `save_one`, `save_multi`
- ✅ **2.2** `on_classes_changed(prev,curr,selected,registry)->bool` in repo handles orphan-resave + schema-diff. VREModel's `_handle_property_changes` → `_refresh_property_ui` (UI only). `_scan_current_properties` now calls `repo.update_last_known_props`.
- ✅ **2.3** Dialogs + BulkEditor call repo: `ConfirmDeleteDialog→vm.delete→repo.delete`, `SaveResourceDialog→vm.create_resource→repo.create`, `BulkEditor→repo.save_multi`; listens to `repo.resources_saved` to notify model.
- ✅ **2.4** `ErrorDialogVM` now connects to `repo.error_occurred` directly (not `model.error_occurred`).

**Commit Phase 2 as one commit** after 2.4 is done.

---

## REMAINING PHASES

### Phase 3 — Embed PaginationBar + StatusLabel into ResourceList.tscn
- Move `PaginationBar` and `StatusLabel` nodes from `visual_resources_editor_window.tscn` into `ui/resource_list/resource_list.tscn` as children.
- Remove their VM assignments from `visual_resources_editor_window.gd._ready()`.
- `resource_list.gd` assigns `%PaginationBar.vm` and `%StatusLabel.vm`.
- **Commit:** one commit.

### Phase 4 — Fatten ResourceListVM (owns pagination + selection + sorting)
- `ResourceListVM` creates `PaginationManager` + `SelectionManager` internally.
- Subscribes directly to `repo.resources_reset` / `resources_delta` → sort + paginate + emit rows.
- New method `handle_row_click(path, ctrl, shift)` → writes `session.selected_paths`.
- `ResourceRowVM` takes `list_vm` instead of full `VREModel`.
- Delete `StatusLabelVM` + `PaginationBarVM`; absorb into `ResourceListVM` signals: `pagination_state_changed(page,total)`, `status_text_changed(visible,selected)`.
- VREModel loses `_on_resources_reset/delta/_on_page_*` handlers.
- **Commit:** one commit.

### Phase 5 — Delete VREModel (3 sub-commits)
**5a** `Window._ready` wires services directly:
  - `fs_listener.script_classes_updated → class_registry.rebuild`
  - `class_registry.classes_changed → repo.on_classes_changed` (lambda reads session)
  - `fs_listener.filesystem_changed → repo.scan_for_changes` (lambda reads session+registry)
  - `ClassSelectorVM` listens to `class_registry.classes_changed` for rename/delete (logic from `VREModel._on_classes_changed:202-224`).

**5b** VMs take services directly (no VREModel):
  - `ClassSelectorVM.new(session, class_registry)`
  - `SubclassFilterVM.new(session)`
  - `ToolbarVM.new(session, resource_repo)`
  - `ResourceListVM.new(session, resource_repo, class_registry)`
  - `BulkEditor` wired with `session` + `resource_repo`.

**5c** Delete `core/vre_model.gd` + `.uid` sidecar.

### Phase 6 — Dialog simplification
- Delete `error_dialog_vm.gd`, `confirm_delete_dialog_vm.gd`, `save_resource_dialog_vm.gd`.
- Dialogs become thin: `ErrorDialog.show(msg)`, `ConfirmDeleteDialog.show(paths)`, `SaveResourceDialog.show(class_name)`.
- Window wires: `repo.error_occurred → error_dialog.show`, `toolbar_vm.delete_requested → confirm_delete.show`, `toolbar_vm.create_requested → save_dialog.show`.
- Delete `Dialogs.gd` script if no logic remains.

### Phase 7 — Cleanup
- Fix `ResourceFieldLabel` StyleBox mutation: call `.duplicate()` before mutating theme stylebox.
- Delete unused `.gd` + `.uid` pairs (grep `class_name` first).
- Delete decorative VMs that became empty forwarders after Phase 5.

---

## Key files reference

| File | Role |
|------|------|
| `core/vre_model.gd` | **Will be deleted** in Phase 5c |
| `core/resource_repository.gd` | Central disk I/O owner (grows through Phase 2) |
| `core/class_registry.gd` | Class map + property scanning |
| `core/selection_manager.gd` | Now path-based; no restore() |
| `core/data_models/session_state_model.gd` | `selected_paths: Array[String]` (Phase 1) |
| `view_models/resource_list_vm.gd` | Grows into pagination+selection owner (Phase 4) |
| `ui/visual_resources_editor_window.gd` | Becomes composition root (Phase 5b) |

## Constraints
- **Never commit unless user says so.** User tests in Godot first.
- **No headless Godot** — user runs Godot themselves for UID generation + testing.
- **Pause after each sub-item** (e.g. 2.3, 2.4) and wait for "continue".
- UI in `.tscn`; `%UniqueNode` convention; UIDs not paths in `preload/load`.
- One commit per phase (not per sub-item).
