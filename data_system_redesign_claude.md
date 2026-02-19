# Database System Redesign — Summary

## Architecture

- `Database` (Resource) → `tables: Array[DataTable]` → each `DataTable` has `table_name` + `instances: Array[DataItem]`
- Single `.tres` at `res://database/res/database.tres`
- Generated `.gd` scripts in `res://database/res/table_structures/` ARE the schema
- Schema read via `GDScript.get_script_property_list()` reflection + `temp.get(prop_name)` for defaults
- Filtered by `PROPERTY_USAGE_EDITOR` flag to exclude inherited/base properties
- `DatabaseManager` is the single orchestrator (absorbed old DataTypeRegistry)
- `ResourceGenerator` owns `PropertyType` enum and generates `@export` typed scripts
- Inspector-driven instance editing via `EditorInterface.inspect_object()`
- `BulkEditProxy` uses `_get_property_list()`/`_get()`/`_set()` for dynamic Inspector properties
- `DataItem` is a clean empty base class — `script.new()` provides defaults
- `table_structures/` hidden from Godot FileSystem dock via `.gdignore` (git-trackable)

## Completed Changes

### Phase 1 — Core Redesign
- Eliminated `DataTypeDefinition`, `DataTypeRegistry`, `JSONPersistence`
- Schema now read via `get_script_property_list()` + `PROPERTY_USAGE_EDITOR` filter
- `Database.tables: Array[DataTable]` replaces old schemas/instances dicts
- `DataItem` cleaned to empty base class (removed `get_type_name`, `to_dict`, `from_dict`)
- `ResourceGenerator` generates simple `@export` scripts (no `_init()`)

### Phase 2 — UI & Path Cleanup
- Renamed `data_type_editor` → `tables_editor`
- Path changed to `res://database/res/` (ready for `json/`, `db/` backends)
- `table_saved` signal wired to instance editor `reload()`
- `_scan_filesystem()` after table changes

### Phase 3 — Bug Fixes & UI Polish
1. **Null guard for scene editing** — `db_manager_window`, `tables_editor`, `data_instance_editor` return early when `database_manager` is null (scene opened in editor, not via toolbar)
2. **Setter-based initialization** — children use `var database_manager: set = _set_database_manager` with `_initialized` flag so init happens when parent assigns the value (children `_ready()` fires before parent `_ready()` in Godot)
3. **CACHE_MODE_REPLACE** — `get_table_properties()` and `_create_data_item()` use `ResourceLoader.CACHE_MODE_REPLACE` to bypass script cache after regeneration
4. **Inspector focus** — `inspector.grab_focus()` after `inspect_object()` so user notices the Inspector updating
5. **property_editor_row scene** — converted from code-built UI to `.tscn` with `@onready` references and `DefaultValueContainer` for swapping editor controls
6. **Default label fix** — "Default:" label is now a permanent scene node, only the editor control inside `DefaultValueContainer` gets swapped on type change
7. **Fixed sizes** — consistent `custom_minimum_size` on all property row controls for orderly display
8. **`.gdignore` instead of dot-prefix** — `table_structures/` uses `.gdignore` to hide from Godot FileSystem dock while remaining git-trackable

### Phase 4 — Terminology Rename (type → table)
- Renamed all "type" references to "table" across codebase for consistency
- `DataTable.type_name` → `DataTable.table_name`
- `DatabaseManager`: `has_type` → `has_table`, `get_type_properties` → `get_table_properties`, `type_has_property` → `table_has_property`, `add_type` → `add_table`, `update_type` → `update_table`, `remove_type` → `remove_table`, `types_changed` → `tables_changed`
- All `type_name` params/vars → `table_name` throughout
- Scene node names: `TypeList` → `TableList`, `TypeSelector` → `TableSelector`, etc.
- UI labels: "Data Types" → "Tables", "Type Name:" → "Table Name:", etc.
- Updated `database.tres` serialized field names

## Pending — Phase 5: Unified Runtime Access & Individual Instance Files

### Known Bug (deferred)
- **Inspector not showing new fields after table edit** — after editing a table schema in Tables Editor, clicking a DataItem in the instance editor still shows old properties in the Inspector until Godot is refreshed.

### Problems to Solve

**1. No runtime/code access**
`DatabaseManager` is a `RefCounted` created only in `database_manager_toolbar.gd` — editor-only, not accessible from game code or `@tool` scripts.

**2. Hardcoded paths**
All paths (`res://database/res/`, `table_structures/`, `database.tres`) are hardcoded constants. Designer data lives in `res://` but user/runtime data needs `user://` or custom paths.

**3. Items not referenceable in `@export`**
Currently all DataItems are **sub-resources embedded inside `database.tres`**. This means:
```gdscript
@export var level: Level  # ← Inspector shows Resource picker, but no Level .tres files exist to pick from
```
Sub-resources inside a `.tres` are not individually addressable in the Inspector. You can't select "Level #2" from a dropdown — it doesn't appear in the filesystem.

### Proposal

#### A. Single `DatabaseManager` autoload (not two-layer)
- Convert `DatabaseManager` from `RefCounted` to `Node` (required for autoload)
- Register as autoload via `add_autoload_singleton()` in the plugin
- Works everywhere: editor UI, `@tool` scripts, runtime game code
- Full API: create tables, add/remove instances, save, load — all from code
- Editor-only features (like `_scan_filesystem()`, `_load_fresh_script()`) guarded by `Engine.is_editor_hint()`

#### B. Configurable paths
`DatabaseManager` has a default `base_path` that can be overridden:

```gdscript
const DEFAULT_BASE_PATH := "res://database/res/"
var base_path: String = DEFAULT_BASE_PATH
var structures_path: String:
    get: return base_path.path_join("table_structures/")
var instances_path: String:
    get: return base_path.path_join("instances/")
var database_path: String:
    get: return base_path.path_join("database.tres")
```

For multiple databases (e.g., designer data + user data):
```gdscript
var user_db = DatabaseManager.create_context("user://saves/database/")
user_db.add_instance("UserLevel")
```

#### C. Instance referencing — two options compared

Instances need to be referenceable from `@export` properties in game scripts (e.g., `level_button` needs to know which Level it corresponds to). Two approaches:

---

##### Option 1: Individual `.tres` files per instance

Each DataItem saved as its own `.tres` file. `database.tres` references them via `ext_resource`.

**Storage layout:**
```
res://database/res/
  database.tres                         ← Registry: tables + ext_resource refs
  table_structures/
    level.gd                            ← Schema (class_name Level extends DataItem)
  instances/
    level/
      level_0.tres                      ← Individual Level instance
      level_1.tres
      level_2.tres
```

**Usage in game scripts:**
```gdscript
@export var level: Level  # ← Resource picker in Inspector → browse to level_0.tres
```

**Pros:**
- Most Godot-native — `@export var level: Level` just works with Resource picker
- Drag-and-drop from FileSystem dock
- Each file individually version-controllable (clean git diffs)
- Direct reference to the actual Resource object — no lookup needed

**Cons:**
- Many files (one per instance across all tables)
- File naming convention needed (by index? by name property?)
- Renaming/reordering instances means renaming/moving files
- `instances/` folder must NOT have `.gdignore` (Godot needs to see the files)
- Runtime data at `user://` also creates individual files
- If a table has 100 instances → 100 files in a folder

---

##### Option 2: Generated enum IDs with stable values (recommended)

Instances stay embedded in `database.tres` (current approach). A generated `.gd` enum file per table provides type-safe ID references. Each instance has two fields on `DataItem` base class:
- `name: String` — human-readable name set by the designer (becomes the enum key)
- `id: int` — auto-assigned permanent int (becomes the enum value), never reused

**The stability problem:** If enum values were sequential (0, 1, 2) and you delete instance 1, all `@export` references using value 2 now point to the wrong instance. The solution: **auto-incrementing persistent IDs** — like a database primary key. Each `DataTable` tracks a `_next_id` counter. New instances get the current counter value, then the counter increments. Deleting an instance does NOT decrement the counter — that ID is retired forever.

**Storage layout:**
```
res://database/res/
  database.tres                         ← All instances embedded (same as current)
  table_structures/
    level.gd                            ← Schema (class_name Level extends DataItem)
  ids/
    level_ids.gd                        ← Auto-generated enum file
    achievement_ids.gd
```

**Generated enum file (`level_ids.gd`):**
```gdscript
class_name LevelIds

## Auto-generated by DatabaseManager — do not edit manually

enum Id {
    FOREST = 0,
    DESERT = 1,
    CAVE = 3,       # id 2 was deleted — value 2 is never reused
    VOLCANO = 4,
}
```
The enum keys come from each instance's `name` property (uppercased, snake_cased). The enum values are the instance's `id` — permanent, never reused, never shifted.

**Example lifecycle:**
```
1. Create FOREST  → id = 0, _next_id becomes 1
2. Create DESERT  → id = 1, _next_id becomes 2
3. Create SWAMP   → id = 2, _next_id becomes 3
4. Create CAVE    → id = 3, _next_id becomes 4
5. Delete SWAMP   → _next_id stays 4 (id 2 is retired)
6. Create VOLCANO → id = 4, _next_id becomes 5
   Enum: FOREST=0, DESERT=1, CAVE=3, VOLCANO=4  ← no gaps cause problems
```
Any `@export var level_id: LevelIds.Id` that was set to `DESERT` (1) still works — the value 1 always means DESERT.

**Usage in game scripts:**
```gdscript
# In level_button.gd
@export var level_id: LevelIds.Id  # ← Dropdown in Inspector: FOREST, DESERT, CAVE, VOLCANO

# At runtime — get the actual DataItem
var level: Level = DatabaseManager.get_by_id("Level", level_id)
print(level.background_color)
```

**How it works:**
- `DataItem` base class gets `name: String` (designer-facing name) and `id: int` (system-assigned)
- `DataTable` gets `_next_id: int` counter (persisted in `database.tres`)
- When a new instance is created: `instance.id = table._next_id; table._next_id += 1`
- When instances are saved, `ResourceGenerator` regenerates the enum `.gd` file
- `DatabaseManager.get_by_id("Level", LevelIds.Id.FOREST)` scans instances for `id == 0` (or uses a cached dict for O(1) lookup)
- If an instance's `name` is renamed, the enum key changes → Godot shows compile errors for stale references (compile-time safety)
- Reordering instances in the list has zero effect on enum values
- Deleting an instance retires its `id` forever

**Pros:**
- Fewer files — one `.gd` per table, not one `.tres` per instance
- Type-safe enum with IDE autocomplete (`LevelIds.Id.FOREST`)
- Inspector shows a clean dropdown (not a file browser)
- `database.tres` stays as single file (simpler storage, simpler backups)
- **Stable values** — reordering or deleting instances never corrupts existing `@export` references
- Enum is a compile-time contract — renaming an instance ID breaks references visibly
- Works naturally with `user://` paths (no individual files to manage)

**Cons:**
- Extra lookup step: `@export` gives you an int, need `DatabaseManager.get_by_id()` to get the Resource
- Enum file must be regenerated when instances are added/removed/renamed
- Instances need a unique `name` property (designer must fill it in)
- Enum keys must be valid GDScript identifiers (no spaces, no special chars)
- Enum values have gaps after deletions (cosmetic, not functional)

---

##### Comparison summary

| Aspect | Option 1 (.tres files) | Option 2 (enum IDs) |
|--------|----------------------|---------------------|
| `@export` type | `Level` (Resource) | `LevelIds.Id` (enum int) |
| Inspector UX | File browser / drag-drop | Clean dropdown |
| Files created | 1 per instance | 1 per table |
| Lookup needed | No (direct reference) | Yes (`get_by_id()`) |
| Instance naming | File name convention | `name` property |
| Git diffs | Per-file changes | Single database.tres |
| Compile-time safety | File missing = error | Enum key missing = error |
| `user://` runtime data | Individual files | Single .tres |

---

#### D. `.gdignore` consideration
- `table_structures/` keeps `.gdignore` (schema scripts are an implementation detail)
- `ids/` must NOT have `.gdignore` (Godot needs to see enum files for `class_name` registration)
- For export: add `res://database/res/table_structures/*.gd` to export include filters
- If using Option 1: `instances/` must NOT have `.gdignore`

### Usage After Implementation (with Option 2 — enum IDs)

```gdscript
# In editor — @tool script configuring level_buttons
@export var level_id: LevelIds.Id  # dropdown: FOREST, DESERT, CAVE

func _ready():
    var level: Level = DatabaseManager.get_by_id("Level", level_id)
    configure_button(level.background_color)

# From code — reading all levels
var levels = DatabaseManager.get_data_items("Level")
for level in levels:
    print(level.background_color)

# From code — creating a table (works in editor or runtime)
DatabaseManager.add_table("UserProgress", [
    {name = "level_id", type = ResourceGenerator.PropertyType.INT, default = 0},
    {name = "completed", type = ResourceGenerator.PropertyType.BOOL, default = false}
])

# Runtime — user data with different path
DatabaseManager.base_path = "user://saves/database/"
DatabaseManager.add_instance("UserProgress")

# Multiple database contexts
var designer_db = DatabaseManager  # autoload, uses res://database/res/
var user_db = DatabaseManager.create_context("user://saves/database/")
```

### Files to Change
- `core/database_manager.gd` — convert to `Node`, configurable paths, `get_by_id()` with cached dict, full API
- `core/database_classes/data_item.gd` — add `name: String` + `id: int` properties
- `core/database_classes/data_table.gd` — add `_next_id: int` counter
- `core/storage/resource_storage_adapter.gd` — support configurable paths
- `utils/resource_generator.gd` — configurable paths + enum `.gd` file generation
- `database_manager_plugin.gd` — `add_autoload_singleton("DatabaseManager", ...)`
- `database_manager_toolbar.gd` — remove `DatabaseManager.new()`, use autoload
- `ui/db_manager_window.gd` — get `DatabaseManager` from autoload
- `ui/data_instance_editor/data_instance_editor.gd` — show `name` + `id` columns

### Open Questions
1. **Multiple databases**: Should `DatabaseManager` support multiple `base_path` contexts simultaneously, or is one active path at a time enough?
2. **Migration**: Existing `database.tres` has embedded sub-resources with no `name` or `id` field — auto-generate from index?
