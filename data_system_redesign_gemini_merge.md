# Data System Redesign: Merged Analysis

This document consolidates findings from two independent analyses of the `DatabaseManager` system. It highlights the strong consensus on critical architectural flaws and synthesizes the best recommendations from both perspectives.

## 1. Consensus: The Critical Flaws
Both tools agreed on these fundamental issues that must be addressed immediately:

*   **Monolithic Storage (`database.tres`):** The current system saves *all* tables and *all* instances into a single file. This is a critical risk for:
    *   **Version Control:** Guaranteed merge conflicts if two designers work simultaneously.
    *   **Scalability:** Save/Load times increase linearly with project size.
    *   **Granularity:** Impossible to load a subset of data.
*   **"God Object" Architecture:** The `DatabaseManager` class (approx. 600 lines) does too much: Schema CRUD, Instance CRUD, Reflection, File I/O, Inheritance logic, and Runtime lookups. This makes it fragile and hard to test.
*   **Editor/Runtime Coupling:** The same class is used for the Editor Plugin and the Runtime Autoload, mixing heavy generation logic with lightweight runtime needs.
*   **Fragile Array-Based Deletion:** `remove_instance` using array indices is dangerous and prone to deleting the wrong item if the list shifts.

## 2. Unique Insights & "Good Catch" Items

### From Claude's Analysis
*   **Lack of Undo/Redo:** The system completely lacks integration with `EditorUndoRedoManager`. Any accidental deletion is permanent. This is a severe UX deficiency for an editor tool.
*   **Dual-Instance State:** The Editor Toolbar creates a *new* `DatabaseManager` instance, separate from the Runtime Autoload instance. This leads to split-brain states where the editor doesn't see runtime changes.
*   **Performance Leaks:**
    *   `_load_fresh_script()` creates throwaway GDScript objects repeatedly for reflection.
    *   `_scan_filesystem()` is triggered too frequently (after every single operation), causing massive editor freezes on large projects.
*   **Cleanup:** `.gd.uid` files are left behind when classes are deleted.

### From Gemini's Analysis
*   **Resource References vs. IDs:** Currently, foreign keys are stored as `int` IDs. This is brittle. Gemini recommends using native **Resource References** (`@export var weapon: WeaponResource`).
    *   *Benefit:* Godot handles renames/moves automatically. "Go to Definition" works in the inspector.
*   **Circular Dependency Risk:** The code generation strategy needs to be careful about `class_name` cyclic dependencies, which can crash the Godot editor.
*   **File-System as Database:** Proposed a concrete directory structure for the redesign.

## 3. Contradictions & Proposed Resolutions

### Conflict 1: Storage Granularity
*   **Claude Suggests:** Split storage to **Per-Table** files (e.g., `tables/Enemies.tres`).
*   **Gemini Suggests:** Split storage to **Per-Instance** files (e.g., `data/enemies/goblin.tres`).
*   **Resolution:** **Go with Per-Instance (Gemini).**
    *   *Reasoning:* Per-table storage is a half-measure. If two designers tweak two different enemies, they still conflict on `Enemies.tres`. Per-instance storage (like standard Godot assets) eliminates merge conflicts almost entirely and allows for lazy-loading specific assets.

### Conflict 2: Foreign Keys
*   **Claude Suggests:** Keep IDs but build a complex "Update FKs on Rename" system.
*   **Gemini Suggests:** Switch to `Resource` references.
*   **Resolution:** **Go with Resource References (Gemini).**
    *   *Reasoning:* Don't fight the engine. Godot is designed to track Resource paths and UIDs. Using `Weapon` instead of `weapon_id` gives you drag-and-drop support, broken-link detection, and automatic rename handling for free.

## 4. The Unified Redesign Plan

### Phase 1: Storage & Data Model (The Foundation)
1.  **Explode the Monolith:**
    *   Change `DataTable` to **not** store instances array.
    *   Create a folder structure: `res://database/data/<table_name>/<instance_name>.tres`.
    *   Update `DatabaseManager` to scan these folders to populate lists.
2.  **Native Resources:**
    *   Update `ResourceGenerator` to generate properties as `Resource` types (or specific class types) instead of `int` IDs where possible.
    *   Keep the generated Enum files (`*_ids.gd`) purely for code-based lookups (e.g., `DB.get_item(ItemIds.SWORD)`).

### Phase 2: Architecture Refactor (The Cleanup)
1.  **Split the God Object:**
    *   `SchemaManager`: Handles `.gd` generation, reflection, and table metadata.
    *   `InstanceManager`: Handles creation, deletion, and file I/O of `.tres` files.
    *   `RuntimeDB`: A lightweight, read-only singleton for the game to use (no editor logic).
2.  **Fix the State:**
    *   Ensure the Editor Toolbar uses the *Singleton* instance (or a shared service) so it shares state with the rest of the editor.

### Phase 3: UX & Safety (The Polish)
1.  **Implement Undo/Redo:** Wrap every `create`, `delete`, and `update` call in `EditorUndoRedoManager` actions.
2.  **Optimize:** Cache reflection results to avoid `_load_fresh_script` spam. Debounce `_scan_filesystem` calls.
3.  **Safety:** Change delete operations to target by **ID/Filename**, never by array index.

## Final Verdict
The system is a solid prototype with "good bones" (the generated script approach is excellent). However, it is not production-ready due to the monolithic file storage and lack of undo support. Implementing the **Per-Instance Storage** and **Undo/Redo** are the non-negotiable next steps.
