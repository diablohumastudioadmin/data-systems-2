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

## DONE — Phases 3, 4, 5

- ✅ **Phase 3** — PaginationBar + StatusLabel are children of `resource_list.tscn`; `resource_list.gd` assigns their `vm`.
- ✅ **Phase 4** — `ResourceListVM` owns `SelectionManager` + `PaginationManager` internally; subscribes directly to repo signals; has `handle_row_click(path,ctrl,shift)`; `ResourceRowVM` takes `list_vm`; `StatusLabelVM` + `PaginationBarVM` deleted.
- ✅ **Phase 5** — `vre_model.gd` deleted. Window wires services directly. All VMs take `session` + services. `ClassSelectorVM` listens to `class_registry.classes_changed`.

---

## REMAINING PHASES

### ~~Phase 6 — Dialog simplification~~ (SKIPPED — dialog VMs kept for testability)

### Phase 6 — Cleanup
- Fix `ResourceFieldLabel` StyleBox mutation: call `.duplicate()` before mutating theme stylebox.
- Delete unused `.gd` + `.uid` pairs (grep `class_name` first).
- Delete decorative VMs that became empty forwarders after Phase 5.

---

## Key files reference

| File | Role |
|------|------|
| `core/resource_repository.gd` | Central disk I/O owner |
| `core/class_registry.gd` | Class map + property scanning |
| `core/selection_manager.gd` | Path-based; no restore() |
| `core/data_models/session_state_model.gd` | `selected_paths: Array[String]` |
| `view_models/resource_list_vm.gd` | Owns pagination + selection + sorting |
| `ui/visual_resources_editor_window.gd` | Composition root — wires all services + VMs |

## Constraints
- **Never commit unless user says so.** User tests in Godot first.
- **No headless Godot** — user runs Godot themselves for UID generation + testing.
- **Pause after each sub-item** (e.g. 2.3, 2.4) and wait for "continue".
- UI in `.tscn`; `%UniqueNode` convention; UIDs not paths in `preload/load`.
- One commit per phase (not per sub-item).
