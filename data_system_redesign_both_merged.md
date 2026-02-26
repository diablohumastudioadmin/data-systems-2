# Data System Redesign — Final Merged Plan

Consolidated from Claude and Gemini analyses, adjusted for user decisions.

---

## Implementation Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1 (Storage + FK + Enums) | **DONE** | Per-instance `.tres` files, Resource FK, enum gen removed, migration helper |
| Phase 2.2 (Fix dual instance) | **DONE** | Toolbar uses autoload singleton |
| Phase 3.3 (Delete by ID) | **DONE** | `remove_instance()` takes stable ID, not array index |
| Phase 3.5 (Fix `_is_empty_value`) | **DONE** | Handles int, float, Array, Dict, Vector2/3, Color, Resource |
| Phase 3.8 (Debug prints) | **DONE** | Removed `print(id)` and `print("sss")` from toolbar |
| Phase 2.1 (Split god object) | **DONE** | Extract SchemaManager + InstanceManager |
| Phase 3.1 (Schema cache) | TODO | Cache reflection results by file mod time |
| Phase 3.2 (Debounce scan) | TODO | 500ms timer for `_scan_filesystem()` |
| Phase 3.4 (Field name validation) | TODO | GDScript reserved words, DataItem reserved fields |
| Phase 3.6 (FK rename update) | TODO | Update FK refs in other tables on rename |
| Phase 3.7 (Schema change warning) | TODO | Warn before destructive field removal/type change |

### Key implementation decisions (deviating from original plan):
- **Constraints use `_init()` override**, not consts — GDScript disallows redeclaring consts/vars in child classes. Base `DataItem` declares `_required_fields` and `_fk_fields`, generated subclasses set values in `_init()`.
- **`get_field_constraints()` parses source text** — reads `_init()` assignments directly from `.gd` file rather than instantiating the script. Robust when FK target classes don't exist yet.
- **Inspector edits don't auto-save** — in-memory only until explicit "Save All". Window close warns about unsaved changes with Save/Discard dialog.
- **`Database.gd` and `DataTable.gd` kept** — needed for v1→v2 migration compatibility. Can be deleted once all users have migrated.

---

## 1. Unified Priority Table

| # | Priority | Change | Source | Phase | Effort |
|---|----------|--------|--------|-------|--------|
| 1 | Critical | Per-instance `.tres` file storage | Both | 1 | Medium |
| 2 | Critical | Resource-based FK references (replace enum int IDs) | Gemini | 1 | Medium |
| 3 | Critical | Remove enum ID generation entirely | User decision | 1 | Low |
| 4 | Critical | Extract DatabaseManager into SchemaManager + InstanceManager | Claude | 2 | Medium |
| 5 | High | Fix dual DatabaseManager instances (toolbar vs autoload) | Claude | 2 | Low |
| 6 | Medium | Cache schema reflection results | Claude | 3 | Low |
| 7 | Medium | Debounce `_scan_filesystem()` | Claude | 3 | Low |
| 8 | Medium | Delete by stable ID, not array index | Claude | 3 | Low |
| 9 | Medium | Validate field names (GDScript rules + reserved) | Both | 3 | Low |
| 10 | Medium | Fix `_is_empty_value()` for non-string types | Claude | 3 | Low |
| 11 | Medium | Update FK references on table rename | Claude | 3 | Low |
| 12 | Medium | Validate constraints match actual field names | Claude | 3 | Low |
| 13 | Medium | Address circular dependency risk in table refs | Gemini | 3 | Medium |
| 14 | Low | Warn before destructive schema changes | Claude | 3 | Medium |
| 15 | Low | Remove debug prints | Claude | 3 | Trivial |

---

## 2. New File Layout on Disk

```
addons/diablohumastudio/database_manager/
├── database_manager_plugin.gd          (MODIFIED: no more dual instance)
├── database_manager_toolbar.gd         (MODIFIED: uses autoload singleton)
├── core/
│   ├── database_manager.gd             (SLIMMED: ~100 lines, facade only)
│   ├── schema_manager.gd              (NEW: schema CRUD, reflection, inheritance)
│   ├── instance_manager.gd            (NEW: per-file instance CRUD, ID cache)
│   ├── database_classes/
│   │   └── data_item.gd             (UNCHANGED)
│   └── storage/
│       ├── storage_adapter.gd         (MODIFIED: new per-instance methods)
│       └── resource_storage_adapter.gd (MODIFIED: per-instance file I/O)
├── utils/
│   ├── resource_generator.gd          (MODIFIED: no enums, FK → Resource refs,
│   │                                    generates REQUIRED_FIELDS + FK_FIELDS consts)
│   ├── schema_cache.gd               (NEW: caches reflection results)
│   ├── field_validator.gd            (NEW: GDScript name rules, reserved words)
│   └── migration_helper.gd           (NEW: one-time v1→v2 migration)
└── ui/
    ├── db_manager_window.gd/.tscn     (MODIFIED)
    ├── tables_editor/
    │   ├── tables_editor.gd/.tscn     (MODIFIED: field validation, FK as Resource)
    │   └── table_field_editor/
    │       ├── table_field_editor.gd  (MODIFIED: FK dropdown → Resource type)
    │       ├── table_field_editor.tscn
    │       └── type_suggestion_provider.gd (UNCHANGED)
    └── data_instance_editor/
        ├── data_instance_editor.gd/.tscn (MODIFIED: delete by ID)
        └── bulk_edit_proxy.gd            (UNCHANGED)


database/res/                              (user data directory — filesystem IS the database)
├── table_structures/                      (schema = these .gd files exist)
│   ├── leveldat.gd                        (generated schema scripts)
│   ├── allyleveldata.gd
│   └── resourceproviderleveldata.gd
└── instances/                             (data = per-table subdirectories)
    ├── leveldat/
    │   └── level_1.tres                   (individual DataItem files)
    ├── userleveldata/
    │   └── a.tres
    ├── allyleveldata/                     (empty — no instances)
    └── resourceproviderleveldata/
        └── iron_chest.tres

DELETED entirely:
  database/res/database.tres               (no longer needed — filesystem is the DB)
  database/res/ids/                        (all *_ids.gd and .gd.uid files)
  core/database_classes/database.gd        (Database class removed)
  core/database_classes/data_table.gd      (DataTable class removed)
```

---

## 3. New Architecture

```
                       ┌──────────────────────────┐
                       │  database_manager_plugin  │
                       │  (EditorPlugin)           │
                       └──────────┬───────────────┘
                         registers│autoload    creates toolbar
                                  │                  │
                                  ▼                  ▼
                          ┌───────────┐    ┌────────────────────┐
                          │ DBManager │◄───│ DataManagerToolbar │
                          │ (autoload)│    │ (uses autoload,    │
                          └─────┬─────┘    │  NOT own instance) │
                                │          └────────────────────┘
                                │                     │
                                ▼                     ▼
                   ┌─────────────────────┐   ┌──────────────────┐
                   │  DatabaseManager    │   │ DbManagerWindow  │
                   │  (thin facade)      │◄──│ (UI root)        │
                   │  ~100 lines         │   └────────┬─────────┘
                   │                     │         ┌──┴──┐
                   │  signals:           │         │     │
                   │   data_changed      │         ▼     ▼
                   │   tables_changed    │   ┌────────┐ ┌──────────┐
                   └───┬─────────┬───────┘   │Tables  │ │Instance  │
                       │         │           │Editor  │ │Editor    │
                       ▼         ▼           └────────┘ └──────────┘
              ┌─────────────┐ ┌──────────────┐
              │ SchemaManager│ │InstanceManager│
              │ ~250 lines  │ │ ~200 lines    │
              ├─────────────┤ ├───────────────┤
              │ add_table() │ │ add_instance()│
              │ update_     │ │ remove() by ID│
              │ rename_     │ │ save()        │
              │ remove_     │ │ load_all()    │
              │ get_fields()│ │ get_items()   │
              │ get_chain() │ │ get_by_id()   │
              │ inheritance │ │ id_cache      │
              └──┬──────┬───┘ └──┬────────┬───┘
                 │      │        │        │
                 │      ▼        ▼        │
                 │  ┌──────────┐  │       │
                 │  │ Schema   │  │       │
                 │  │ Cache    │  │       │
                 │  └──────────┘  │       │
                 ▼                ▼       ▼
          ┌──────────────┐  ┌──────────────────┐
          │ Resource     │  │ StorageAdapter   │
          │ Generator    │  │ (per-instance    │
          │ (code gen,   │  │  file I/O)       │
          │  no enums)   │  └────────┬─────────┘
          └──────┬───────┘           │
                 │                   │
                 ▼                   ▼
        table_structures/*.gd   instances/<table>/*.tres

    THE FILESYSTEM IS THE DATABASE:
    ┌─────────────────────────────────────────────┐
    │  Schema = table_structures/*.gd exist        │
    │  Data   = instances/<table>/*.tres exist      │
    │  Constraints = REQUIRED_FIELDS + FK_FIELDS   │
    │               consts inside the .gd scripts  │
    │  Parent = get_base_script() reflection       │
    │  No database.tres. No DataTable. No Database.│
    └─────────────────────────────────────────────┘
```

### Responsibility Split

| Class | What it owns | ~Lines |
|-------|-------------|--------|
| `DatabaseManager` | Facade, signal relay, lifecycle, `reload()`, public API delegates | ~100 |
| `SchemaManager` | Table CRUD, script gen, reflection, inheritance, constraints (reads consts from scripts) | ~250 |
| `InstanceManager` | Instance CRUD per-file, ID generation (time-hash), ID cache, lazy loading | ~200 |
| `SchemaCache` | Cache `_load_fresh_script()` results, invalidate on schema change | ~60 |
| `FieldValidator` | GDScript identifier rules, reserved words, duplicate detection | ~80 |
| `ResourceGenerator` | Code gen only (no enums), FK generates `@export var x: Weapon`, generates `REQUIRED_FIELDS` + `FK_FIELDS` consts | ~300 |
| `MigrationHelper` | One-time v1→v2 data conversion (delete after migration) | ~80 |

---

## 4. Phase 1 — Storage & Data Model

### 4.1 Per-Instance File Storage

**`DataTable` and `Database` classes are eliminated.** The filesystem IS the database:
- A table "exists" if `table_structures/<name>.gd` exists
- Instances live as individual `.tres` files in `instances/<table_name>/`
- Constraints are embedded as consts in the generated `.gd` script
- Parent table is determined via `get_base_script()` reflection
- IDs use time-based hash (no centralized `next_id` counter, no merge conflicts)

**Generated script now includes constraint consts:**

```gdscript
# table_structures/enemy.gd (AFTER — generated)
@tool
class_name Enemy
extends DataItem

## Auto-generated DataItem subclass for Enemy table
## Generated by Data Systems Plugin — do not edit manually

const REQUIRED_FIELDS: Array[String] = ["health", "damage"]
const FK_FIELDS: Dictionary = { "weapon": "Weapon" }

@export var health: int = 0
@export var damage: int = 0
@export var weapon: Weapon = null
```

**ID generation — time-based hash (no counter):**

```gdscript
# In InstanceManager:
func _generate_id() -> int:
    return ResourceUID.create_id()  # Godot built-in, unique per call
```

No centralized `next_id` means no shared state to conflict on in VCS.

**StorageAdapter becomes instance-only** (no more `load_database`/`save_database`):

```gdscript
# storage_adapter.gd — new interface (database.tres is gone)
func save_instance(item: DataItem, table_name: String, base_path: String) -> Error
func load_instances(table_name: String, base_path: String) -> Array[DataItem]
func delete_instance(item: DataItem, table_name: String, base_path: String) -> Error
func rename_instance_file(item: DataItem, old_name: String, table_name: String, base_path: String) -> Error
func delete_table_instances_dir(table_name: String, base_path: String) -> Error
```

**ResourceStorageAdapter implementation:**

```
save_instance()  →  ResourceSaver.save(item, "instances/<table>/<name>.tres")
load_instances() →  DirAccess.open("instances/<table>/"), load each .tres
delete_instance()→  DirAccess.remove_absolute(item.resource_path)
```

Filename sanitization: `item.name` → `snake_case`, strip special chars, append `_<id>` if collision.

**`get_table_names()` — scans filesystem:**

```gdscript
# In SchemaManager:
func get_table_names() -> Array[String]:
    var names: Array[String] = []
    var dir := DirAccess.open(structures_path)
    dir.list_dir_begin()
    var file := dir.get_next()
    while file != "":
        if file.ends_with(".gd"):
            # Load script to read class_name (or infer from filename)
            names.append(file.get_basename().capitalize())
        file = dir.get_next()
    return names
```

**`get_field_constraints()` — reads consts from script:**

```gdscript
func get_required_fields(table_name: String) -> Array[String]:
    var script := _load_table_script(table_name)
    var consts := script.get_script_constant_map()
    return consts.get("REQUIRED_FIELDS", [])

func get_fk_fields(table_name: String) -> Dictionary:
    var script := _load_table_script(table_name)
    var consts := script.get_script_constant_map()
    return consts.get("FK_FIELDS", {})
```

**`get_parent_table()` — reflection, no stored string:**

```gdscript
func get_parent_table(table_name: String) -> String:
    var script := _load_table_script(table_name)
    var base: GDScript = script.get_base_script()
    if base == null or base.get_class() == "DataItem":
        return ""
    # Extract class_name from base script
    return _get_class_name_from_script(base)
```

**Lazy loading**: Instances are NOT loaded at startup. They load on first `get_data_items(table_name)` call and are cached in `_instance_cache`.

```
                User selects "LevelDat" in UI
                        │
                        ▼
             InstanceManager.get_data_items("LevelDat")
                        │
                        ▼
            Is _instance_cache["LevelDat"] populated?
                 │                    │
                YES                  NO
                 │                    │
                 ▼                    ▼
           return cached     storage.load_instances("LevelDat")
                                      │
                                      ▼
                              scan instances/leveldat/
                              load each .tres file
                                      │
                                      ▼
                              cache + build id_cache + return
```

### 4.2 Resource-Based FK References

**Before** (current — enum int):
```gdscript
# Generated in leveldat.gd:
@export var weapon_id: WeaponIds.Id = 0

# Inspector shows: enum dropdown (int values)
# Game code:  DBManager.get_by_id("Weapon", item.weapon_id)
```

**After** (Resource reference):
```gdscript
# Generated in leveldat.gd:
@export var weapon: Weapon = null

# Inspector shows: native Resource picker (drag-and-drop)
# Game code:  item.weapon.damage  (direct property access!)
```

**Changes in `resource_generator.gd`:**

```gdscript
# _generate_script_content() — FK handling
# BEFORE:
if fc.has("foreign_key"):
    type_str = "%sIds.Id" % fc["foreign_key"]   # → "WeaponIds.Id"

# AFTER:
if fc.has("foreign_key"):
    type_str = fc["foreign_key"]                  # → "Weapon" (the class name)
```

Default value for Resource FK: `null` (already handled by existing fallback).

**Changes in `table_field_editor.gd`:**

```gdscript
# _apply_fk() — type override
# BEFORE:
%TypeAutocomplete.set_text("%sIds.Id" % fk_table)

# AFTER:
%TypeAutocomplete.set_text(fk_table)
```

### 4.3 Remove Enum Generation

**Delete from `resource_generator.gd`:**
- `generate_enum_file()` method
- `delete_enum_file()` method
- `_generate_enum_content()` method
- `_sanitize_enum_key()` method

**Delete from `database_manager.gd`:**
- `_regenerate_enum()` method
- `ids_path` computed property
- All `_regenerate_enum()` calls in: `add_table`, `add_instance`, `remove_instance`, `save_instances`, `clear_instances`
- All `delete_enum_file()` calls in: `remove_table`, `rename_table`
- All `generate_enum_file()` calls in: `rename_table`

**Delete from disk:**
- Entire `database/res/ids/` directory (all `*_ids.gd` and `*.gd.uid` files)

### 4.4 Add Instance — Before vs After

```
BEFORE:                                      AFTER:

User clicks "Add"                            User clicks "Add"
      │                                            │
      ▼                                            ▼
add_instance(table, name)                    InstanceManager.add_instance(table, name)
      │                                            │
      ├→ script.new()                              ├→ script.new()
      ├→ id = next_id++                            ├→ id = ResourceUID.create_id()
      ├→ table.instances.append(item)              ├→ storage.save_instance(item)
      ├→ save() ──→ writes ENTIRE                  │    └→ writes ONE file:
      │              database.tres                 │       instances/table/name.tres
      ├→ _regenerate_enum()                        ├→ _cache_item()
      │    └→ writes *_ids.gd                      ├→ _request_scan() ──→ debounced 500ms
      ├→ _scan_filesystem() ──→ FULL scan          └→ data_changed.emit()
      └→ data_changed.emit()
                                             (No database.tres write. No enum gen.
                                              No shared counter. Just one .tres file.)
```

---

## 5. Phase 2 — Architecture Refactor

### 5.1 Split the God Object

**Methods moving to `SchemaManager`:**

| From DatabaseManager | To SchemaManager |
|---------------------|------------------|
| `get_table_names()` | scans `table_structures/` directory |
| `has_table()` | checks if `table_structures/<name>.gd` exists |
| `get_table_fields()` (72-93) | uses `SchemaCache` instead of raw `_load_fresh_script()` |
| `table_has_field()` (96-101) | same logic |
| `get_field_constraints()` (104-108) | reads `REQUIRED_FIELDS` + `FK_FIELDS` consts from script |
| `add_table()` (114-141) | generates .gd, creates instances dir |
| `update_table()` (145-184) | regenerates .gd with updated consts |
| `rename_table()` (189-258) | delegates instance file moves to InstanceManager |
| `remove_table()` (262-285) | deletes .gd + delegates instance dir deletion |
| `get_parent_table()` (426-430) | uses `get_base_script()` reflection |
| `get_child_tables()` (433-438) | scans all scripts for matching base |
| `get_own_table_fields()` (442-457) | same logic |
| `get_inheritance_chain()` (462-480) | same logic |
| `_would_create_cycle()` (493-499) | same logic |
| `is_descendant_of()` (503-509) | same logic |
| `_regenerate_child_script()` (513-534) | same logic |
| `_load_fresh_script()` (556-575) | replaced by `SchemaCache` |

**Methods moving to `InstanceManager`:**

| From DatabaseManager | To InstanceManager |
|---------------------|-------------------|
| `get_data_items()` (290-296) | loads from per-file storage (cached) |
| `get_by_id()` (300-311) | uses `_id_cache` |
| `add_instance()` (315-338) | saves individual `.tres`, ID via `ResourceUID.create_id()` |
| `remove_instance()` (341-353) | **now takes ID, not index** |
| `save_instances()` (356-360) | saves all `.tres` files for a table |
| `load_instances()` (363-364) | reloads from disk |
| `clear_instances()` (367-375) | deletes all `.tres` in table dir |
| `get_instance_count()` (378-382) | from cache |
| `_rebuild_id_cache()` (387-393) | private |
| `_rebuild_table_cache()` (395-404) | private |
| `_cache_item()` (407-411) | private |
| `_create_data_item()` (539-551) | same logic |

**DatabaseManager becomes a thin facade (~100 lines):**

```gdscript
@tool
class_name DatabaseManager
extends Node

signal data_changed(table_name: String)
signal tables_changed()

var base_path: String = "res://database/res/"
var schema: SchemaManager       # public
var instances: InstanceManager  # public

var _storage: StorageAdapter

func _ready() -> void:
    _storage = ResourceStorageAdapter.new()
    reload()

func reload() -> void:
    # No database.tres to load — the filesystem IS the database
    if MigrationHelper.needs_migration(base_path):
        MigrationHelper.migrate_v1_to_v2(base_path, _storage)
    schema = SchemaManager.new(base_path)
    instances = InstanceManager.new(_storage, schema, base_path)
    schema.tables_changed.connect(func(): tables_changed.emit())
    instances.data_changed.connect(func(t): data_changed.emit(t))

# Convenience pass-throughs:
func get_table_names() -> Array[String]:
    return schema.get_table_names()
func has_table(n: String) -> bool:
    return schema.has_table(n)
func get_data_items(t: String) -> Array[DataItem]:
    return instances.get_data_items(t)
func get_by_id(t: String, id: int) -> DataItem:
    return instances.get_by_id(t, id)
# ... etc
```

### 5.2 Fix Dual-Instance Problem

**Current bug:**

```
database_manager_plugin.gd:
  add_autoload_singleton("DBManager", ...)   ← instance A (runtime)

database_manager_toolbar.gd:
  database_manager = DatabaseManager.new()   ← instance B (editor) — SEPARATE!
```

**Fix in `database_manager_toolbar.gd`:**

```gdscript
func _enter_tree() -> void:
    clear()
    # Use the autoload singleton — do NOT create a second instance
    if Engine.has_singleton("DBManager"):
        database_manager = Engine.get_singleton("DBManager")
    else:
        # Fallback for editor context
        database_manager = get_node_or_null("/root/DBManager")
    add_item("Launch Data Manager", 0, KEY_F10)
    id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
    if data_manager_window and is_instance_valid(data_manager_window):
        data_manager_window.queue_free()
        data_manager_window = null
    # Do NOT free database_manager — it's the autoload singleton
```

Also: remove `print(id)` and `print("sss")` debug lines.

### 5.3 Runtime Write Access

No separate RuntimeDB needed. The existing `DatabaseManager` autoload works at runtime with full write capabilities. Per-instance file storage makes runtime writes cleaner:

```gdscript
# Runtime game code:
DBManager.instances.add_instance("UserSaveData", "player_session_1")
DBManager.instances.save_instance("UserSaveData", item)
```

For user-generated data in exported builds (`res://` is read-only), a configurable path:

```gdscript
var runtime_base_path: String = "user://database/"
```

This is a future enhancement, not blocking for the redesign.

---

## 6. Phase 3 — UX & Safety

### 6.1 Cache Schema Reflection

**New file: `utils/schema_cache.gd`**

```gdscript
@tool
class_name SchemaCache
extends RefCounted

var _cache: Dictionary = {}  # {script_path: {fields: Array, timestamp: int}}

func get_fields(script_path: String) -> Array[Dictionary]:
    var mod_time := FileAccess.get_modified_time(script_path)
    if _cache.has(script_path) and _cache[script_path].timestamp == mod_time:
        return _cache[script_path].fields
    var fields := _reflect_fields(script_path)
    _cache[script_path] = {fields = fields, timestamp = mod_time}
    return fields

func invalidate(script_path: String) -> void:
    _cache.erase(script_path)
```

Replaces all `_load_fresh_script()` + `script.new()` calls. For a table with 3 levels of inheritance, eliminates 6+ throwaway GDScript objects per UI interaction.

### 6.2 Debounce `_scan_filesystem()`

```gdscript
# In DatabaseManager:
var _scan_timer: Timer

func _ready() -> void:
    if Engine.is_editor_hint():
        _scan_timer = Timer.new()
        _scan_timer.one_shot = true
        _scan_timer.wait_time = 0.5  # 500ms debounce
        _scan_timer.timeout.connect(func():
            EditorInterface.get_resource_filesystem().scan())
        add_child(_scan_timer)

func _request_scan() -> void:
    if _scan_timer:
        _scan_timer.start()  # restarts on each call — only one scan after burst
```

Replace all `_scan_filesystem()` calls with `_request_scan()`.

### 6.3 Delete by Stable ID

**Before:**
```gdscript
func remove_instance(table_name: String, index: int) -> bool:
    table.instances.remove_at(index)
```

**After:**
```gdscript
func remove_instance(table_name: String, id: int) -> bool:
    var item := get_by_id(table_name, id)
    if item == null: return false
    _storage.delete_instance(item, table_name, instances_path)
    _uncache_item(table_name, id)
    data_changed.emit(table_name)
    return true
```

In `data_instance_editor.gd`, tree metadata stores `data_item.id` instead of array index.

### 6.4 Validate Field Names

**New file: `utils/field_validator.gd`**

```gdscript
const GDSCRIPT_RESERVED := ["if", "elif", "else", "for", "while", "match",
    "break", "continue", "pass", "return", "class", "class_name", "extends",
    "is", "as", "self", "signal", "func", "static", "const", "enum", "var",
    "preload", "await", "yield", "assert", "void", "true", "false", "null",
    "not", "and", "or", "in"]

const DATAITEM_RESERVED := ["name", "id", "resource_path", "resource_name", "script"]

static func validate_field_name(name: String, existing: Array[String]) -> String:
    if name.is_empty(): return "Field name cannot be empty"
    if not name.is_valid_identifier(): return "Invalid GDScript identifier"
    if name in GDSCRIPT_RESERVED: return "'%s' is a GDScript reserved word" % name
    if name in DATAITEM_RESERVED: return "'%s' is reserved by DataItem" % name
    if name in existing: return "Duplicate field name"
    return ""
```

Integrate into `table_field_editor.gd` on field name change and `tables_editor.gd` before save.

### 6.5 Fix `_is_empty_value()`

```gdscript
static func _is_empty_value(value: Variant) -> bool:
    if value == null: return true
    if value is String: return value.strip_edges().is_empty()
    if value is int: return value == 0
    if value is float: return is_zero_approx(value)
    if value is Array: return value.is_empty()
    if value is Dictionary: return value.is_empty()
    if value is Vector2: return value == Vector2.ZERO
    if value is Vector3: return value == Vector3.ZERO
    if value is Color: return value == Color(0, 0, 0, 0)
    if value is Resource: return false  # non-null Resource is never "empty"
    return false
```

### 6.6 Update FK References on Table Rename

In `SchemaManager.rename_table()`, after renaming the script, scan all other table scripts for FK references to the old name:

```gdscript
for table_name in get_table_names():
    var fk_fields := get_fk_fields(table_name)  # reads FK_FIELDS const from script
    var changed := false
    for field_name in fk_fields:
        if fk_fields[field_name] == old_name:
            fk_fields[field_name] = new_name
            changed = true
    if changed:
        # Regenerate that table's script with updated FK_FIELDS const + field type
        _regenerate_table_script(table_name, fk_fields)
        _hot_reload_script(table_name)
```

### 6.7–6.8 Minor Fixes

- **Warn before destructive schema changes**: In `tables_editor._on_save_table_pressed()`, compare old vs new fields, show dialog if fields removed or types changed
- **Remove debug prints**: Delete `print(id)` and `print("sss")` from toolbar, convert others to `push_warning()` or remove

---

## 7. Migration Plan (v1 → v2)

```
User opens editor after update
        │
        ▼
DatabaseManager._ready() → reload()
        │
        ▼
MigrationHelper.needs_migration(base_path)?
  (checks: does database.tres exist?)
    │                    │
   NO → done            YES
                         │
                         ▼
    Load old database.tres (v1 format)
                         │
                         ▼
    ┌─ For each DataTable in database.tables: ─────────────┐
    │  1. Create instances/<table_name>/ directory          │
    │  2. For each item in table.instances:                 │
    │     a. Assign time-hash ID (replace old sequential)   │
    │     b. Null out FK enum int fields → null             │
    │        (Resource refs can't auto-migrate from ints)   │
    │     c. Save as instances/<table>/name.tres            │
    │  3. Regenerate .gd script with:                       │
    │     - REQUIRED_FIELDS const (from field_constraints)  │
    │     - FK_FIELDS const (from field_constraints)        │
    │     - Resource FK types instead of enum types         │
    └──────────────────────────────────────────────────────┘
        │
        ▼
    Delete database/res/ids/ directory entirely
        │
        ▼
    Delete database/res/database.tres (no longer needed)
        │
        ▼
    Print migration summary + FK reassignment warning
```

**Key detail**: FK fields that were `WeaponIds.Id` (int enum) become `Weapon` (Resource). The migration sets them to `null` and prints a warning. Users must manually reassign FK references via the Inspector.

---

## 8. FK Reference — Before vs After

```
BEFORE:                                AFTER:

 Schema:                                Schema:
 @export var weapon_id: WeaponIds.Id    @export var weapon: Weapon

 Inspector:                             Inspector:
 enum dropdown (int values)             native Resource picker
                                        (drag-and-drop from FileSystem)

 Stored in .tres:                       Stored in .tres:
 weapon_id = 3                          weapon = ExtResource("uid://...")
                                               → instances/weapon/sword.tres

 Game code:                             Game code:
 var w = DBManager.get_by_id(           item.weapon.damage  (direct access!)
     "Weapon", item.weapon_id)
 w.damage

 On table rename:                       On table rename:
 FK breaks (enum type gone)             Godot tracks Resource UIDs
                                        (auto-updates references)
```

---

## 9. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Migration data loss mid-way | HIGH | Write all new `.tres` files first, only then delete old `database.tres`. Keep backup. |
| FK fields become null after migration | MEDIUM | Print warnings. Document manual reassignment. |
| Filename collisions (duplicate names) | MEDIUM | Append `_<id>` to filename for uniqueness. |
| Instance rename = file rename | MEDIUM | Detect `name` change in Inspector callback, call `storage.rename_instance_file()`. |
| Directory scan performance for `get_table_names()` | LOW | Cache results in SchemaManager, invalidate on add/remove table. |
| Autoload timing in toolbar | LOW | Use `await get_tree().process_frame` or check `Engine.has_singleton()`. |
| Large tables (1000+ instances) | LOW | Lazy loading + caching. Only load selected table. |
| Hot-reload breaks | MEDIUM | Per-instance `.tres` use `CACHE_MODE_REUSE`. Script hot-reload pattern unchanged. |

---

## 10. Recommended Implementation Order

```
Phase 2.2  Fix dual instance ✅ DONE
    │
    ▼
Phase 1    Per-instance files + Resource FK + Remove enums ✅ DONE
    │      (also done: 3.3 delete by ID, 3.5 _is_empty_value, 3.8 debug prints)
    ▼
Phase 2.1  Split god object ← NEXT
    │      Extract SchemaManager + InstanceManager from DatabaseManager
    ▼
Phase 3    Remaining items (any order):
           3.1 Schema cache
           3.2 Debounce scan
           3.4 Field name validation
           3.6 FK rename update
           3.7 Schema change warning
```
