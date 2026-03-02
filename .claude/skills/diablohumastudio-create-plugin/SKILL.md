---
name: diablohumastudio-create-plugin
description: Scaffold a new Godot 4 editor addon following DiabloHumaStudio plugin conventions. Use when the user asks to create a new plugin, addon, or editor tool in this project.
argument-hint: [plugin-name] [DisplayName] [description] [--autoload AutoloadName path/to/script.gd]
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# DiabloHumaStudio — Create Plugin

Scaffold a new Godot 4 editor plugin following this project's conventions.

## Arguments

Parse `$ARGUMENTS` to extract:
- `plugin-name` — snake_case folder name (e.g. `visual_resources_editor`)
- `DisplayName` — human-readable name for plugin.cfg and toolbar (e.g. `Visual Resources Editor`)
- `description` — short description string for plugin.cfg
- `--autoload AutoloadName res://path/to/script.gd` — optional; if present, register an autoload singleton

If any of these are missing or ambiguous, ask the user before proceeding.

---

## Conventions to follow

### File naming
- Folder: `addons/diablohumastudio/<plugin-name>/`
- Main plugin script: `<plugin-name>_plugin.gd`
- Toolbar script: `<plugin-name>_toolbar.gd`
- UI subfolder: `ui/`
- Window scene: `ui/<plugin-name>_window.tscn`
- Window script: `ui/<plugin-name>_window.gd`

### GDScript rules (from CLAUDE.md)
- All tool scripts start with `@tool`
- Visual things are defined in `.tscn` scenes, NOT built in code
- Use `%UniqueNode` directly in code — do NOT wrap in `@onready var` (exception: tight loops)
- `const` / `var` cannot be redeclared in child classes — override values in `_init()` instead

### Toolbar menu
- The toolbar script uses `class_name <PluginName>Toolbar extends DiablohumaStudioToolMenu`
- It preloads the window scene **by UID** (use `preload("uid://...")` — Godot sets UIDs automatically when the file is saved in the editor; during scaffolding use a placeholder comment and note the user must let Godot assign it)
- Menu items use `add_item("Label", id, KEY_<shortcut>)` and connect `id_pressed`
- Opens window with:
  ```gdscript
  window = WindowPksc.instantiate()
  EditorInterface.get_base_control().add_child(window)
  window.popup_centered()
  ```

### Plugin registration
- `plugin.cfg` author is always `"DiabloHumaStudio"`, version `"2.0.0"`
- `project.godot` `[editor_plugins] enabled` array must include the new `plugin.cfg` path

---

## Files to create

### 1. `addons/diablohumastudio/<plugin-name>/plugin.cfg`
```ini
[plugin]

name="<DisplayName>"
description="<description>"
author="DiabloHumaStudio"
version="2.0.0"
script="<plugin-name>_plugin.gd"
```

### 2. `addons/diablohumastudio/<plugin-name>/<plugin-name>_plugin.gd`

**Without autoload:**
```gdscript
@tool
extends DiabloHumaStudioPlugin

const TOOLBAR_MENU_NAME: String = "<DisplayName>"

func _enter_tree() -> void:
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu := <PluginName>Toolbar.new()
	MainToolbarPlugin.add_toolbar_shubmenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)

func _exit_tree() -> void:
	MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
```

**With autoload** (append these lines):
```gdscript
const AUTOLOAD_SCRIPT := "res://addons/diablohumastudio/<plugin-name>/..."

func _enter_tree() -> void:
	add_autoload_singleton("<AutoloadName>", AUTOLOAD_SCRIPT)
	add_toolbar_menu()

func _exit_tree() -> void:
	MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
	remove_autoload_singleton("<AutoloadName>")
```

### 3. `addons/diablohumastudio/<plugin-name>/<plugin-name>_toolbar.gd`
```gdscript
@tool
class_name <PluginName>Toolbar
extends DiablohumaStudioToolMenu

# NOTE: Replace this UID with the real one Godot assigns after saving the .tscn in editor
const <PluginName>WindowPksc = preload("uid://PLACEHOLDER")
var <plugin_name>_window: Window

func _enter_tree() -> void:
	add_item("Launch <DisplayName>", 0, KEY_F3)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	pass

func _on_menu_id_pressed(id: int):
	match id:
		0:
			open_window()

func open_window():
	<plugin_name>_window = <PluginName>WindowPksc.instantiate()
	EditorInterface.get_base_control().add_child(<plugin_name>_window)
	<plugin_name>_window.popup_centered()
```

### 4. `addons/diablohumastudio/<plugin-name>/ui/<plugin-name>_window.gd`
```gdscript
@tool
extends Window

func _on_close_requested() -> void:
	queue_free()
```

### 5. `addons/diablohumastudio/<plugin-name>/ui/<plugin-name>_window.tscn`

Godot scene files require UIDs that the editor assigns. Create this as a text scaffold and tell the user they must open the project in the Godot editor once so Godot can assign real UIDs and update the preload path in the toolbar script.

Minimal scaffold (Godot will regenerate UIDs on first open):
```
[gd_scene format=3 uid="uid://PLACEHOLDER"]

[ext_resource type="Script" uid="uid://PLACEHOLDER" path="res://addons/diablohumastudio/<plugin-name>/ui/<plugin-name>_window.gd" id="1_00000"]

[node name="<PluginName>Window" type="Window"]
oversampling_override = 1.0
position = Vector2i(0, 36)
script = ExtResource("1_00000")

[connection signal="close_requested" from="." to="." method="_on_close_requested"]
```

---

## project.godot update

Read `project.godot`, find the `[editor_plugins]` section, and append the new plugin path to the `enabled` PackedStringArray. Example — existing line:
```
enabled=PackedStringArray("...", "res://addons/diablohumastudio/last_plugin/plugin.cfg")
```
becomes:
```
enabled=PackedStringArray("...", "res://addons/diablohumastudio/last_plugin/plugin.cfg", "res://addons/diablohumastudio/<plugin-name>/plugin.cfg")
```

---

## After scaffolding

Remind the user:
1. Open the project in the Godot editor — Godot will assign real UIDs to the new `.tscn` and `.gd` files
2. Update the `preload("uid://PLACEHOLDER")` in `<plugin-name>_toolbar.gd` with the real UID Godot assigned to the window scene
3. Enable the plugin in **Project → Project Settings → Plugins** if it doesn't appear automatically (the `project.godot` edit should handle this)
4. If an autoload was added, verify it appears in **Project → Project Settings → Autoload**
