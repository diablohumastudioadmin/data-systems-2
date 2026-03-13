# Annotations (Rules)

## UX / Workflow
- Deleting resource files does not require undo/redo; use version control for recovery.
- Bulk edit undo/redo is optional; do not block work on adding it unless explicitly requested.

## GDScript Setters
- Setters must assign the incoming value to the property; do not remove the assignment.

## Resource Loading
- UID-only rule applies to hardcoded paths. Dynamic runtime paths may use string paths.
- `ResourceLoader.CACHE_MODE_REPLACE` is acceptable for this tool to force reloading when class/subclass filters change.

## UI Construction
- Dynamic UI elements must be instantiated from `.tscn` scenes, not created with `Node.new()`.
- Dialog UI should be `.tscn` scenes and instantiated when needed.

## Lambdas
- Lambdas are allowed when they are small, self-contained, and capture local variables (especially dialog instances).
- Prefer direct callables for simple signal forwarding when no local state is captured.

## Typing
- Type loop variables and arrays we create, or arrays from built-in APIs that return typed arrays.
- Leave arrays untyped when they come from built-in APIs that return untyped arrays.
- `Array.map` returns an untyped array; do not force a typed array on the result.

## Scene Structure
- If a parent node has a script but is not an instantiated scene, do not add child nodes in the editor expecting `%UniqueName` access. Either:
  - Create those child nodes in code, or
  - Make the parent a scene, add the children there, set `unique_name_in_owner = true`, and reference with `%`.

## Cleanup
- If a script is unused and not wired anywhere, delete it and its `.uid` sidecar.

## Naming
- Constants should be uppercase with explicit types (e.g., `const RESOURCE_ROW_SCENE: PackedScene = ...`).
