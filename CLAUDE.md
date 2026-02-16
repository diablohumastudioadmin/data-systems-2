# Database Manager Addon — Claude Instructions

## Project Overview
Godot 4 `@tool` editor plugin (`addons/diablohumastudio/database_manager/`) for managing game data tables. Uses generated GDScript Resource classes as both schema and typed instances.

## Workflow
- **Before implementing changes**: write a proposal in `data_system_redesign_claude.md` with problem/fix/files for each item. Wait for user approval.
- **When implementing**: make one git commit per change item. Use clear commit messages.
- **After implementing**: update `data_system_redesign_claude.md` summary section — keep it concise, delete verbose proposals that are now completed.

## Architecture
- See `data_system_redesign_claude.md` for full architecture details.
- `DatabaseSystem` is the single orchestrator. `ResourceGenerator` generates scripts. Inspector-driven editing.
- Schema lives in generated `.gd` files at `res://database/res/table_structures/` (hidden via `.gdignore`).
- Database stored as single `.tres` at `res://database/res/database.tres`.

## Key File Locations
```
core/database_system.gd        — DatabaseSystem (orchestrator)
core/database_classes/          — Database, DataTable, DataItem
core/storage/                   — StorageAdapter, ResourceStorageAdapter
utils/resource_generator.gd     — PropertyType enum + code generation
ui/tables_editor/               — Tables editor (create/edit schemas)
ui/data_instance_editor/        — Instance editor (Tree + Inspector)
ui/db_manager_window.gd         — Window combining both editors
database_manager_toolbar.gd     — EditorPlugin menu integration
```

## GDScript Gotchas
- Use `var table: DataTable = ...` not `var table := ...` when LSP can't infer return types
- Children `_ready()` fires before parent `_ready()` in Godot — use setter-based initialization when parent sets properties on children
- `load()` caches scripts — use `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)` after regenerating `.gd` files
- `EditorInterface.get_resource_filesystem().scan()` is needed after writing files to disk
- `.gdignore` file inside a folder hides it from Godot FileSystem dock but keeps it git-trackable
