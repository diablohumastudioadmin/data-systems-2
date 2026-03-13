# Database Manager Addon — Claude Instructions

## Project Overview
Godot 4 `@tool` editor plugin (`addons/diablohumastudio/database_manager/`) for managing game data tables. Uses generated GDScript Resource classes as both schema and typed instances.

## Workflow
- **Before implementing changes**: write a proposal in `data_system_redesign_claude.md` with problem/fix/files for each item. Wait for user approval.
- **When implementing**: make one git commit per change item. Use clear commit messages.
- **After implementing**: update `data_system_redesign_claude.md` summary section — keep it concise, delete verbose proposals that are now completed.

## UI Convention
- **Visual things must be defined in `.tscn` scenes**, not in `.gd` code — even when dynamically instantiated. Instantiate the scene in code, then configure it (pass arguments, connect signals). Only build UI in code when a scene is truly impossible (e.g. fully procedural runtime generation with no fixed structure).
- **Non-visual nodes (helpers, managers) also belong in `.tscn` scenes** — add them as child nodes in the relevant scene with `unique_name_in_owner = true`, assign their script in the `.tscn`, and reference them via `%NodeName`. Do NOT instantiate non-visual nodes in code (`Node.new()` / `add_child()`) when they have a fixed role in a scene.

## Node References Convention
- **Use `%UniqueNode` directly in code** — do NOT wrap in `@onready var`. Mark the node as "Unique Name in Owner" in the scene (right-click node → "Unique Name in Owner").
- `%NodeName` only works if the node has `unique_name_in_owner = true` set in the `.tscn`. No node reference without this flag. Two nodes in the same scene cannot share the same unique name.
- **Exception**: Only use `@onready var` when the node is accessed in a tight loop (e.g. nested `for` inside `for`), to avoid repeated lookup cost.
- Example: `%MyButton.pressed.connect(...)` instead of `@onready var my_button = $Path/To/MyButton` then `my_button.pressed.connect(...)`

## Type Inference Convention
- **Never use `:=` for type inference** — always use explicit types with `=`. GDScript's `:=` fails when the right-hand side doesn't have a clear type (e.g. properties from `%UniqueNode`). Write `var pos: Vector2 = %Node.position` instead of `var pos := %Node.position`.

## GDScript Inheritance Gotcha
- **GDScript disallows redeclaring `const` or `var` (properties) in child classes** if the same name exists in a parent class. This applies to all consts and exported properties — the child will fail to compile with "already exists in parent class". The correct pattern: declare the variable in the base class, then override its **value** in `_init()` of each subclass.

## ButtonGroup as Shared Resource (Single-Select Rows)
- To make a group of Buttons mutually exclusive, create a `ButtonGroup` as a `.tres` file (e.g. `row_button_group.tres`), assign it in the `.tscn` on the Button node, and ensure `resource_local_to_scene = false` (the default for external resources). All instances that share this resource file will be part of the same exclusive group.
- **Limitation**: ButtonGroup does not support Ctrl+Click multi-select. For multi-select scenarios, manage selection state manually in the parent script (set `toggle_mode = true` on buttons, deselect all + select clicked on normal click, toggle on Ctrl+Click).
- **TODO**: Create a skill `diablohumastudio-shared-button-group` to scaffold a ButtonGroup `.tres` resource and wire it to a scene node.

## Running Tests
- **Godot binary**: `Godot4.6` (alias or full path: `/Volumes/Fer/RespaldoFER/Documentos/GODOT/Editor/Executables/Godot_v4.6-stable_macos.universal.app/Contents/MacOS/Godot`)
- **Command**: `Godot4.6 --headless --path . --script tests/test_<name>.gd`
- Test files: `tests/test_redesign.gd`, `tests/test_constraints.gd`, `tests/test_inheritance.gd`, `tests/test_autocomplete.gd`
