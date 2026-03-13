# Visual Resources Editor — Architecture Redesign Proposal

## Goals
1. Visual components only manage visual tasks, receiving only what they need.
2. `IncludeSubclassesCheck` moved to the Window, next to `ClassSelector`.
3. `ResourceList` receives only `resources + columns` — does no scanning itself.
4. `HeaderRow` and `ResourceRow` receive only what they render.
5. `ResourceRow` can display all subclass columns, leaving blank fields it doesn't own.
6. Window logic split into focused inner objects if it grows too large.

---

## Component Responsibilities (New)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  VisualResourcesEditorWindow                                             │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Top Bar (HBox)                                                    │   │
│  │  [ClassSelector]  [☐ Include Subclasses]  [⚠ some classes...]   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ ResourceList                                                      │   │
│  │  receives: resources: Array[Resource], columns: Array[Dictionary] │   │
│  │  emits:    resource_selected, delete_requested, create_requested  │   │
│  │                                                                   │   │
│  │  [HeaderRow]  ← columns only                                      │   │
│  │  [ResourceRow × N]  ← resource + columns                         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ StateManager (Node, not visual)                                  │    │
│  │  owns:    current_class, include_subclasses                      │    │
│  │  does:    scan resources, compute union columns                  │    │
│  │  listens: EditorFileSystem.filesystem_changed                    │    │
│  │  emits:   data_changed(resources, columns)                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

```
EditorFileSystem
  filesystem_changed
        │
        ▼
  StateManager.rescan()
        │
        ▼ emits data_changed(resources, columns)
        │
  Window._on_state_data_changed()
        │
        ├──▶ ResourceList.set_data(resources, columns)
        │         │
        │         ├──▶ HeaderRow.set_columns(columns)
        │         │
        │         └──▶ for each resource:
        │                ResourceRow.setup(resource, columns)
        │
        └── (class names refresh)
              ClassSelector.set_classes_in_dropdown(names)
```

```
User selects class in ClassSelector
        │ emits class_selected(name)
        ▼
  Window._on_class_selected(name)
        │
        ▼
  StateManager.set_class(name)
        │
        ▼ emits data_changed(resources, columns)
        │
  (same flow as above)
```

```
User toggles IncludeSubclassesCheck
        │ toggled(pressed)
        ▼
  Window._on_include_subclasses_toggled(pressed)
        │
        ▼
  StateManager.set_include_subclasses(pressed)
        │
        ▼ emits data_changed(resources, columns)
```

---

## Inspector / Save Flow

My recommendation: **Window listens to `EditorInspector.property_edited`** — not ResourceList.

Reasoning:
- ResourceList is now purely visual (display + user intent signals). It should not know the editor inspector exists.
- The Window already knows which resource is being inspected (it sent it to the inspector when the row was selected).
- When a property is edited, Window saves the resource and tells ResourceList to refresh just that one row.
- StateManager is not involved — this is not a filesystem scan event (file didn't change on disk in a way that requires re-indexing the list).

```
User edits a property in the EditorInspector
        │ emits property_edited(property_name)
        ▼
  Window._on_inspector_property_edited(property)
        │
        ├── ResourceSaver.save(_inspected_resource)
        │
        └── ResourceList.refresh_row(_inspected_resource.resource_path)
                  │
                  └── ResourceRow.update_display()
```

If bulk editing is involved, Window still owns the logic: it knows all selected resources, applies the value to each, saves each, and tells ResourceList to refresh each row.

---

## ResourceList Data Contract

ResourceList becomes a pure display-and-intent component:

```gdscript
# Called by Window when state changes (class switch, subclass toggle, filesystem change)
func set_data(resources: Array[Resource], columns: Array[Dictionary]) -> void

# Called by Window after saving a single edited resource
func refresh_row(resource_path: String) -> void

# Signals emitted upward — Window acts on them
signal resource_selected(resource: Resource)
signal delete_requested(paths: Array[String])
signal create_requested()
signal refresh_requested()
```

ResourceList does **not** call `ProjectClassScanner`, does **not** read `IncludeSubclassesCheck`, does **not** call `ResourceSaver`. It just renders what it's given and reports user intent.

---

## Column Union (Subclass Support)

StateManager computes the union of all properties when include_subclasses is on:

```
class_name: Weapon (base)
  properties: [name, damage, weight]

subclass: Sword extends Weapon
  properties: [name, damage, weight, blade_length]

subclass: Bow extends Weapon
  properties: [name, damage, weight, range]

→ columns (union): [name, damage, weight, blade_length, range]
```

HeaderRow renders all 5 column labels.

Each ResourceRow receives the same 5 columns:
```
Sword resource:  name | damage | weight | blade_length | (blank)
Bow resource:    name | damage | weight | (blank)      | range
```

ResourceRow checks if the property exists on that resource's script before reading its value. If it doesn't, the cell is left blank.

```gdscript
# In ResourceRow.setup(resource, columns):
var _owned_props: Dictionary = {}
for p in resource.get_script().get_script_property_list():
    _owned_props[p.name] = true

# In _set_label_value(label, col):
if not _owned_props.has(col.name):
    label.text = ""
    return
# ... render value normally
```

---

## StateManager — What It Does

`StateManager` is a plain `Node` (no visual, added as child of Window in the `.tscn`):

```gdscript
class_name VREStateManager
extends Node

signal data_changed(resources: Array[Resource], columns: Array[Dictionary])

var _current_class_name: String = ""
var _include_subclasses: bool = false

func set_class(class_name_str: String) -> void
func set_include_subclasses(value: bool) -> void
func rescan() -> void       # re-runs scan + emits data_changed
func _on_filesystem_changed() -> void  # connected in _ready()

# Internally calls ProjectClassScanner, loads resources, computes union columns
```

Window connects to `StateManager.data_changed` and forwards to `ResourceList.set_data()`.

---

## Window Scene Structure (New)

```
Window (VisualResourcesEditorWindow)
├── StateManager (Node)                   ← new inner node, not visual
└── MarginContainer
    └── VBox
        ├── TopBar (HBoxContainer)
        │   ├── ClassSelector             ← unchanged
        │   ├── IncludeSubclassesCheck    ← moved here from ResourceList
        │   └── SubclassWarningLabel      ← moved here from ResourceList
        ├── HSeparator
        └── ResourceList                  ← now receives data, doesn't scan
```

---

## What Changes in Each File

| File | Change |
|------|--------|
| `visual_resources_editor_window.tscn` | Add StateManager node; move IncludeSubclassesCheck + warning to TopBar |
| `visual_resources_editor_window.gd` | Connect StateManager; handle property_edited; pass data to ResourceList; read IncludeSubclassesCheck directly |
| `resource_list.tscn` | Remove IncludeSubclassesCheck + warning Label from toolbar |
| `resource_list.gd` | Remove scanning logic; expose `set_data()` and `refresh_row()`; emit intent signals only |
| `resource_row.gd` | Add `_owned_props` check; show blank for columns not owned by that resource |
| `header_row.gd` | No change needed |
| `state_manager.gd` | **New file** — scanning + column union + filesystem listener |

---

## Open Question: Bulk Edit Ownership

In the current code, bulk editing lives in ResourceList. In the new design:
- ResourceList can still own bulk-edit visual state (which rows are selected, highlight styles).
- But **applying bulk values and saving** should move to Window (it's a save operation, not a visual one).
- ResourceList emits `bulk_edit_property_changed(property, value, selected_paths)` → Window saves each.

This keeps the pattern consistent: ResourceList = visual + intent, Window = logic + persistence.
