# Database Manager Addon — Claude Instructions

## Project Overview
Godot 4 `@tool` editor plugin (`addons/diablohumastudio/database_manager/`) for managing game data tables. Uses generated GDScript Resource classes as both schema and typed instances.

## Workflow
- **Before implementing changes**: write a proposal in `data_system_redesign_claude.md` with problem/fix/files for each item. Wait for user approval.
- **When implementing**: make one git commit per change item. Use clear commit messages.
- **After implementing**: update `data_system_redesign_claude.md` summary section — keep it concise, delete verbose proposals that are now completed.

## UI Convention
- **Visual things must be defined in `.tscn` scenes**, not in `.gd` code — even when dynamically instantiated. Instantiate the scene in code, then configure it (pass arguments, connect signals). Only build UI in code when a scene is truly impossible (e.g. fully procedural runtime generation with no fixed structure).
