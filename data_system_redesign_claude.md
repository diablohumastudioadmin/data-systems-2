# Data System — Architecture Analysis & Critique

## System Overview

A Godot 4 `@tool` editor plugin for managing game designer data (spreadsheet-level CRUD) with bulk editing, table inheritance, foreign keys, and generated enum IDs for type-safe `@export` references at runtime.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EDITOR (plugin)                                │
│  ┌──────────────────┐   ┌────────────────────────────────────────────┐ │
│  │ DatabaseManager   │   │  db_manager_window.tscn                   │ │
│  │ Plugin            │──▶│  ┌──────────────┐  ┌────────────────────┐ │ │
│  │ (EditorPlugin)    │   │  │ TablesEditor  │  │DataInstanceEditor  │ │ │
│  └──────┬───────────┘   │  │ (schema CRUD) │  │(instance CRUD +   │ │ │
│         │               │  │               │  │ bulk edit)         │ │ │
│         │               │  └──────┬────────┘  └────────┬───────────┘ │ │
│  ┌──────▼───────────┐   └────────┼─────────────────────┼────────────┘ │
│  │DataManagerToolbar│            │                     │              │
│  │(menu + F10 key)  │            ▼                     ▼              │
│  └──────────────────┘   ┌────────────────────────────────────────┐    │
│                         │        DatabaseManager                 │    │
│                         │       (core orchestrator)              │    │
│                         │  - table CRUD     - instance CRUD      │    │
│                         │  - inheritance    - ID cache            │    │
│                         │  - enum gen       - schema reflection   │    │
│                         └───┬──────────┬─────────────┬───────────┘    │
│                             │          │             │                │
│                      ┌──────▼──┐ ┌─────▼──────┐ ┌───▼──────────┐    │
│                      │Database │ │Resource    │ │Storage       │    │
│                      │DataTable│ │Generator   │ │Adapter       │    │
│                      │DataItem │ │(code gen)  │ │(.tres I/O)   │    │
│                      └─────────┘ └────────────┘ └──────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘

                        RUNTIME (autoload: DBManager)
┌─────────────────────────────────────────────────────────────────────────┐
│  Same DatabaseManager class, loaded as autoload                        │
│  Game code: DBManager.get_by_id("LevelDat", LevelDatIds.Id.FOREST)    │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
 Designer edits in UI
        │
        ▼
 DatabaseManager.add_table() / update_table() / add_instance()
        │
        ├──▶ ResourceGenerator.generate_resource_class()
        │         └──▶ writes .gd file to table_structures/
        │
        ├──▶ ResourceGenerator.generate_enum_file()
        │         └──▶ writes _ids.gd to ids/
        │
        ├──▶ StorageAdapter.save_database()
        │         └──▶ writes database.tres
        │
        └──▶ Hot-reload: load() + source_code + reload(true)
                  └──▶ All existing instances see updated schema
```

### File Layout on Disk

```
database/res/
├── database.tres                   ← single Database resource (all tables + instances)
├── table_structures/
│   ├── leveldat.gd                 ← generated DataItem subclass (IS the schema)
│   ├── allyleveldata.gd
│   └── resourceproviderleveldata.gd  ← extends allyleveldata.gd (inheritance)
└── ids/
    ├── leveldat_ids.gd             ← enum LevelDatIds.Id { LEVEL_1 = 1 }
    └── allyleveldata_ids.gd
```

---

## What Works Well

### 1. Schema = Generated Script (excellent decision)
Using generated `.gd` files as both schema and typed Resource classes is elegant. It eliminates schema/instance drift, gives you Godot Inspector editing for free, and makes the data available as typed classes at runtime. The reflection via `get_script_property_list()` closes the loop cleanly.

### 2. Stable IDs + Enum Generation
The `next_id` counter that never reuses IDs, combined with generated enum files, gives game code compile-time-safe references (`LevelDatIds.Id.FOREST`). This is a solid pattern for game data systems.

### 3. Hot-Reload Mechanism
`load(CACHE_MODE_REUSE)` + `source_code =` + `reload(true)` is the correct Godot approach. All instances stay connected to the same GDScript object. This avoids the common pitfall of severed script references.

### 4. Inspector-Driven Instance Editing
Instead of building custom editors for every field type, you delegate to Godot's Inspector. This gets you native editors for Color, Vector2, Resource pickers, enums, etc. — for zero custom widget code. Smart.

### 5. Table Inheritance
`extends "res://path/to/parent.gd"` in generated scripts gives you real GDScript inheritance. Polymorphic queries, inherited field display, cycle detection — all present and correct.

### 6. BulkEditProxy Pattern
Exposing a single dynamic field via `_get_property_list()` to reuse the Inspector for bulk editing is clever and lightweight.

---

## Problems & Critique

### CRITICAL — DatabaseManager is a God Object (597 lines, ~15 responsibilities)

`DatabaseManager` does too many things:
- Table CRUD (add/update/rename/remove)
- Instance CRUD (add/remove/save/clear/load)
- Schema reflection (get_table_fields, get_own_table_fields, table_has_field)
- Inheritance logic (get_parent, get_children, get_chain, is_descendant, cycle detection, polymorphic queries)
- ID caching (rebuild, cache_item)
- Enum generation coordination
- Legacy migration
- Filesystem scanning
- Storage coordination
- Signal emission

This makes the class hard to test, hard to extend, and any change risks breaking unrelated functionality. When you add features like "import from CSV" or "undo/redo" or "JSON export" — they'll all get piled into this one class.

**Recommendation**: Extract focused classes:
- `TableSchemaService` — table CRUD + schema reflection + inheritance logic
- `InstanceService` — instance CRUD + ID cache
- `DatabaseManager` — thin facade that delegates to the above + storage + signals

### HIGH — No Undo/Redo Support

Every operation (add/delete table, add/delete instance, bulk edit, field edit) is immediately persisted with no undo. In an editor tool, this is a significant UX gap. Game designers will accidentally delete things.

Godot provides `UndoRedo` (or `EditorUndoRedoManager` in editor plugins). Every mutating operation should push an undo action.

**Recommendation**: Integrate `EditorUndoRedoManager`. Each operation becomes a `create_action()` / `add_do_method()` / `add_undo_method()` / `commit_action()` pair.

### HIGH — Single .tres File = Scalability Bottleneck

All tables and all instances live in one `database.tres`. For a game with 50 tables and 5,000 instances:
- Every save rewrites the entire file
- Git conflicts on every merge (binary-ish format, single file)
- Load time grows linearly with total data
- No partial loading possible

**Recommendation**: Consider splitting to one `.tres` per table (e.g., `tables/LevelDat.tres`). The `Database` resource would then hold references, not inline data. This also dramatically improves git diffing and merge conflict resolution.

### HIGH — Two Separate DatabaseManager Instances (Editor vs Runtime)

The toolbar creates its own `DatabaseManager.new()` for editor use, while the plugin registers a separate autoload instance for runtime. These are completely independent objects with independent caches and state. If runtime code modifies data through the autoload, the editor window won't see it, and vice versa.

```
Plugin._enter_tree():
  add_autoload_singleton("DBManager", ...)   ← runtime instance

Toolbar._enter_tree():
  database_manager = DatabaseManager.new()   ← editor instance (separate!)
```

**Recommendation**: In editor mode, have the toolbar locate and use the autoload instance instead of creating a new one. Or accept the split but document why.

### MEDIUM — `_load_fresh_script()` Creates Throwaway GDScript Objects

Every call to `get_table_fields()` creates a brand-new anonymous GDScript object and a `script.new()` temporary instance, just to read the schema. This happens on:
- Every `_load_table()` in both editors
- Every `_refresh_instances()` (for column headers)
- Every `get_own_table_fields()` call (which calls `get_table_fields()` twice — once for self, once for parent)
- Every inheritance chain build

For a table with 3 levels of inheritance, loading it calls `_load_fresh_script()` at least 6+ times.

**Recommendation**: Cache schema reflection results. Invalidate the cache only when a table is updated/renamed. A simple `_schema_cache: Dictionary = {}` keyed by table name would eliminate all redundant parsing.

### MEDIUM — Constraints Stored Separately from Schema

Field constraints (`required`, `foreign_key`) live in `DataTable.field_constraints`, separate from the generated `.gd` schema. This creates a dual source of truth:
- The `.gd` file defines field names and types
- The `DataTable` stores constraints

If someone manually edits the `.gd` file or if the field name changes, the constraints dictionary becomes orphaned. There's no validation that constraint keys match actual field names.

**Recommendation**: Either embed constraints as comments/annotations in the generated `.gd` file (parseable on load), or add a validation step in `reload()` that prunes orphaned constraints.

### MEDIUM — `_is_empty_value()` Required Validation Is Too Permissive

```gdscript
func _is_empty_value(value: Variant) -> bool:
    if value == null: return true
    if value is String and value.strip_edges().is_empty(): return true
    return false
```

An `int` of `0`, a `Vector2.ZERO`, an empty `Array`, a `Color.BLACK` — none of these are considered "empty." If a required field is `int`, the designer can leave it at default `0` and the system considers the constraint satisfied. This makes "Required" meaningless for non-String, non-null types.

**Recommendation**: Extend `_is_empty_value()` to handle `0` for numeric types, empty arrays/dicts, `Vector.ZERO`, etc. Or reconsider what "required" means — perhaps it should only apply to String and Resource fields where "empty" is unambiguous.

### MEDIUM — `remove_instance()` Uses Array Index, Not ID

```gdscript
func remove_instance(table_name: String, index: int) -> bool:
    ...
    table.instances.remove_at(index)
```

Callers pass array indices, which are fragile — if the array changes between getting the index and calling remove, you delete the wrong item. The multi-delete in `data_instance_editor.gd` works around this by sorting indices in reverse, but it's error-prone.

**Recommendation**: Change to `remove_instance(table_name: String, id: int) -> bool` using the stable ID. The ID cache already supports this lookup.

### MEDIUM — No Field Name Validation

The table editor doesn't validate field names. A designer could create a field named:
- `name` or `id` (clashes with DataItem base fields)
- `resource_path` (clashes with Resource internals)
- `123invalid` (invalid GDScript identifier)
- Field with spaces (invalid identifier)

The generated `.gd` would have a syntax error and `reload()` would fail silently.

**Recommendation**: Validate field names against: GDScript identifier rules, `_BASE_FIELD_NAMES`, and existing field names in the same table (no duplicates).

### MEDIUM — `rename_table()` Doesn't Update Foreign Key References

If table "Enemy" has a foreign key to "LevelDat" and you rename "LevelDat" to "Level", the FK constraint in "Enemy" still points to "LevelDat". The generated type `LevelDatIds.Id` in Enemy's `.gd` becomes invalid.

**Recommendation**: In `rename_table()`, scan all tables' `field_constraints` and update any `foreign_key` values that reference the old name.

### LOW — `_scan_filesystem()` Called Too Frequently

`EditorInterface.get_resource_filesystem().scan()` triggers a full project re-import. It's called after every:
- `add_table()`
- `update_table()`
- `remove_table()`
- `rename_table()`
- `_regenerate_enum()` (which is called on every instance add/remove/save)

Adding 10 instances triggers 10 full filesystem scans.

**Recommendation**: Debounce or batch `_scan_filesystem()`. Or use `update_file()` for individual files (which you already do in some paths) and only `scan()` when class_names change.

### LOW — Debug Print Statements Left In

```gdscript
# database_manager_toolbar.gd
func _on_menu_id_pressed(id: int):
    print(id)            # ← debug leftover
    ...

func open_data_manager_window() -> void:
    print("sss")         # ← debug leftover
```

**Recommendation**: Remove debug prints or replace with `print_debug()` / conditional logging.

### LOW — `delete_resource_class()` Doesn't Delete `.gd.uid` Files

Per known gotchas, `.gd.uid` files must be deleted alongside `.gd` files. `delete_resource_class()` only removes the `.gd`:

```gdscript
static func delete_resource_class(...) -> Error:
    ...
    return dir.remove(file_path.get_file())  # only .gd, not .gd.uid
```

**Recommendation**: Also remove `file_path + ".uid"` in both `delete_resource_class()` and `delete_enum_file()`.

### LOW — No Confirmation Before Schema Changes That Drop Data

Renaming a field or changing its type in the schema doesn't warn the designer that existing instance data for that field will be lost. The script gets regenerated, `reload(true)` preserves what it can, but type-incompatible values silently become defaults.

**Recommendation**: Compare old and new field lists before `update_table()`. If fields were removed or types changed, show a warning listing affected instances.

---

## Structural Recommendations Summary

| Priority | Change | Effort | Impact |
|----------|--------|--------|--------|
| Critical | Extract DatabaseManager into focused services | Medium | Maintainability, testability |
| High | Add Undo/Redo via EditorUndoRedoManager | High | UX, designer trust |
| High | Split database.tres into per-table files | Medium | Git workflow, scalability |
| High | Resolve dual DatabaseManager instances | Low | Correctness |
| Medium | Cache schema reflection results | Low | Performance |
| Medium | Validate field names | Low | Robustness |
| Medium | Fix `remove_instance()` to use ID not index | Low | Correctness |
| Medium | Update FK references on table rename | Low | Correctness |
| Medium | Fix `_is_empty_value()` for non-string types | Low | Correctness |
| Medium | Validate constraints match actual fields | Low | Robustness |
| Low | Debounce `_scan_filesystem()` | Low | Performance |
| Low | Delete `.gd.uid` files | Low | Cleanliness |
| Low | Warn before destructive schema changes | Medium | UX |
| Low | Remove debug prints | Trivial | Cleanliness |

---

## What I Would Not Change

- **Schema = generated script** — this is the right approach, don't add a separate schema layer
- **Inspector-based editing** — don't build custom property editors, Godot's are better
- **BulkEditProxy** — the dynamic property approach is clean
- **Hot-reload mechanism** — CACHE_MODE_REUSE + reload(true) is correct
- **Enum ID generation** — valuable for game code, keep it
- **StorageAdapter abstraction** — good extension point for future JSON/SQLite backends
- **Table inheritance** — valuable feature, well-implemented

The system is well-designed for its current scope. The main risk is that the monolithic `DatabaseManager` will become increasingly painful as you add features. Addressing the god object problem now will make everything else (undo/redo, import/export, new storage backends) significantly easier to implement.
