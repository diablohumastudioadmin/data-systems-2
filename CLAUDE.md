# Database Manager Addon — Claude Instructions

## Project Overview
Godot 4 `@tool` editor plugin (`addons/diablohumastudio/database_manager/`) for managing game data tables. Uses generated GDScript Resource classes as both schema and typed instances.

## Workflow
- **Before implementing changes**: write a proposal in `data_system_redesign_claude.md` with problem/fix/files for each item. Wait for user approval.
- **When implementing**: make one git commit per change item. Use clear commit messages.
- **After implementing**: update `data_system_redesign_claude.md` summary section — keep it concise, delete verbose proposals that are now completed.
- Deleting resource files does not require undo/redo; use version control for recovery.
- Bulk edit undo/redo is optional; do not block work on adding it unless explicitly requested.

## UI Convention
- **Visual things must be defined in `.tscn` scenes**, not in `.gd` code — even when dynamically instantiated. Instantiate the scene in code, then configure it (pass arguments, connect signals). Only build UI in code when a scene is truly impossible (e.g. fully procedural runtime generation with no fixed structure).
- **Non-visual nodes (helpers, managers) also belong in `.tscn` scenes** — add them as child nodes in the relevant scene with `unique_name_in_owner = true`, assign their script in the `.tscn`, and reference them via `%NodeName`. Do NOT instantiate non-visual nodes in code (`Node.new()` / `add_child()`) when they have a fixed role in a scene.
- **Script-only nodes (no `.tscn`)**: When a node has no child nodes and no significant static/editor-configured properties, use a standalone `.gd` script extending the base type (e.g. `extends ConfirmationDialog`). Add the node in the parent `.tscn` with its base type and assign the script there. This avoids near-empty `.tscn` files. All self-wiring (signal connections, runtime configuration) goes in the script's `_ready()`.
- **Dialog UI** with children or complex editor-configured layout should be `.tscn` scenes. Simple dialogs (no children, fully configured at runtime) should be script-only nodes in the parent scene.
- **Lambdas** are allowed when they are small, self-contained, and capture local variables (especially dialog instances). Prefer direct callables for simple signal forwarding when no local state is captured.

## Node References Convention
- **Use `%UniqueNode` directly in code** — do NOT wrap in `@onready var`. Mark the node as "Unique Name in Owner" in the scene (right-click node → "Unique Name in Owner").
- `%NodeName` only works if the node has `unique_name_in_owner = true` set in the `.tscn`. No node reference without this flag. Two nodes in the same scene cannot share the same unique name.
- **Exception**: Only use `@onready var` when the node is accessed in a tight loop (e.g. nested `for` inside `for`), to avoid repeated lookup cost.
- Example: `%MyButton.pressed.connect(...)` instead of `@onready var my_button = $Path/To/MyButton` then `my_button.pressed.connect(...)`
- **Do NOT wrap a child node's method in an inline lambda just to connect it** — methods are already Callables. Write `signal.connect(%Node.method)` directly instead of `signal.connect(func(): %Node.method())`. Example: `%ResourceList.create_requested.connect(%ResourceCRUD.create)` not `%ResourceList.create_requested.connect(func(): %ResourceCRUD.create())`.
- **Exception**: a lambda IS needed when the signal passes arguments that must be forwarded: `%ResourceList.delete_requested.connect(func(paths: Array[String]): %ResourceCRUD.delete(paths))`.

## Scene Structure
- If a parent node has a script but is **not** an instantiated scene, do not add child nodes in the editor expecting `%UniqueName` access. Either:
  - Create those child nodes in code, or
  - Make the parent a scene, add the children there, set `unique_name_in_owner = true`, and reference with `%`.

## Resource Loading Convention
- **Always use UIDs in `load()` and `preload()`**, not string paths. UIDs survive file renames and moves without breaking references. Use `uid://xxxxxxxxxxxx` format: `preload("uid://xxxxxxxxxxxx")`. Find a file's UID in the `.uid` sidecar (for `.gd` scripts) or in the file header (`uid="uid://..."` on the first line of `.tscn` / `.tres` files).
- **UID-only rule applies to hardcoded paths.** Dynamic runtime paths (computed at runtime) may use string paths.
- **`load()` on a `.gd` file returns a GDScript Resource, not an instance.** Calling `.new()` on a loaded script that extends Node creates a detached node — it is NOT added to the scene tree automatically. To instantiate a Node-derived script: use `class_name` and call `MyClassName.new()`, or `load("res://path.gd").new()`. Do NOT confuse `load("script.gd")` (returns the script resource) with instantiating it (`.new()` on the result).
- **Never cache `EditorFileSystemDirectory` references** in member variables. Godot frees and recreates the directory tree on every filesystem rescan (`EditorFileSystem.scan()`). A cached reference becomes a freed object, causing "previously freed" errors on next use. Always call `EditorInterface.get_resource_filesystem().get_filesystem()` fresh when needed.
- `ResourceLoader.CACHE_MODE_REPLACE` is acceptable to force reloading when class/subclass filters change.
- **After creating a new `.gd` file that will be referenced in a `.tscn`**, run Godot headless so it imports the file and generates the `.uid` sidecar before adding the reference. Without this, the `.tscn` can only reference by path (fragile). Command: `/Volumes/Fer/RespaldoFER/Documentos/GODOT/Editor/Executables/Godot_v4.6.1-stable_macos.universal.app/Contents/MacOS/Godot --headless --path . --quit`

## Type Inference Convention
- **Never use `:=` for type inference** — always use explicit types with `=`. GDScript's `:=` fails when the right-hand side doesn't have a clear type (e.g. properties from `%UniqueNode`). Write `var pos: Vector2 = %Node.position` instead of `var pos := %Node.position`.
- **Always type `for` loop variables** — write `for row: ResourceRow in _rows:` not `for row in _rows:`.
- Type loop variables and arrays we create, or arrays from built-in APIs that return typed arrays.
- Leave arrays untyped when they come from built-in APIs that return untyped arrays.
- `Array.map` returns an untyped array; do not force a typed array on the result.

## GDScript Setters
- Setters must assign the incoming value to the property; do not remove the assignment.

## GDScript Inheritance Gotcha
- **GDScript disallows redeclaring `const` or `var` (properties) in child classes** if the same name exists in a parent class. This applies to all consts and exported properties — the child will fail to compile with "already exists in parent class". The correct pattern: declare the variable in the base class, then override its **value** in `_init()` of each subclass.

## Naming & Constants
- Constants should be uppercase with explicit types (e.g., `const RESOURCE_ROW_SCENE: PackedScene = ...`).

## Cleanup
- If a script is unused and not wired anywhere, delete it and its `.uid` sidecar.

## ButtonGroup as Shared Resource (Single-Select Rows)
- To make a group of Buttons mutually exclusive, create a `ButtonGroup` as a `.tres` file (e.g. `row_button_group.tres`), assign it in the `.tscn` on the Button node, and ensure `resource_local_to_scene = false` (the default for external resources). All instances that share this resource file will be part of the same exclusive group.
- **Limitation**: ButtonGroup does not support Ctrl+Click multi-select. For multi-select scenarios, manage selection state manually in the parent script (set `toggle_mode = true` on buttons, deselect all + select clicked on normal click, toggle on Ctrl+Click).
- **TODO**: Create a skill `diablohumastudio-shared-button-group` to scaffold a ButtonGroup `.tres` resource and wire it to a scene node.

## Running Tests
- **Godot binary**: `Godot4.6` (alias or full path: `/Volumes/Fer/RespaldoFER/Documentos/GODOT/Editor/Executables/Godot_v4.6-stable_macos.universal.app/Contents/MacOS/Godot`)
- **Command**: `Godot4.6 --headless --path . --script tests/test_<name>.gd`
- Test files: `tests/test_redesign.gd`, `tests/test_constraints.gd`, `tests/test_inheritance.gd`, `tests/test_autocomplete.gd`
