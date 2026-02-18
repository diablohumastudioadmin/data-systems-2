# Database System Redesign — Summary

## Architecture

- `Database` (Resource) → `tables: Array[DataTable]` → each `DataTable` has `table_name` + `instances: Array[DataItem]`
- Single `.tres` at `res://database/res/database.tres`
- Generated `.gd` scripts in `res://database/res/table_structures/` ARE the schema
- Schema read via `GDScript.get_script_property_list()` reflection + `temp.get(prop_name)` for defaults
- Filtered by `PROPERTY_USAGE_EDITOR` flag to exclude inherited/base properties
- `DatabaseSystem` is the single orchestrator (absorbed old DataTypeRegistry)
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
1. **Null guard for scene editing** — `db_manager_window`, `tables_editor`, `data_instance_editor` return early when `database_system` is null (scene opened in editor, not via toolbar)
2. **Setter-based initialization** — children use `var database_system: set = _set_database_system` with `_initialized` flag so init happens when parent assigns the value (children `_ready()` fires before parent `_ready()` in Godot)
3. **CACHE_MODE_REPLACE** — `get_table_properties()` and `_create_data_item()` use `ResourceLoader.CACHE_MODE_REPLACE` to bypass script cache after regeneration
4. **Inspector focus** — `inspector.grab_focus()` after `inspect_object()` so user notices the Inspector updating
5. **property_editor_row scene** — converted from code-built UI to `.tscn` with `@onready` references and `DefaultValueContainer` for swapping editor controls
6. **Default label fix** — "Default:" label is now a permanent scene node, only the editor control inside `DefaultValueContainer` gets swapped on type change
7. **Fixed sizes** — consistent `custom_minimum_size` on all property row controls for orderly display
8. **`.gdignore` instead of dot-prefix** — `table_structures/` uses `.gdignore` to hide from Godot FileSystem dock while remaining git-trackable

### Phase 4 — Terminology Rename (type → table)
- Renamed all "type" references to "table" across codebase for consistency
- `DataTable.type_name` → `DataTable.table_name`
- `DatabaseSystem`: `has_type` → `has_table`, `get_type_properties` → `get_table_properties`, `type_has_property` → `table_has_property`, `add_type` → `add_table`, `update_type` → `update_table`, `remove_type` → `remove_table`, `types_changed` → `tables_changed`
- All `type_name` params/vars → `table_name` throughout
- Scene node names: `TypeList` → `TableList`, `TypeSelector` → `TableSelector`, etc.
- UI labels: "Data Types" → "Tables", "Type Name:" → "Table Name:", etc.
- Updated `database.tres` serialized field names
