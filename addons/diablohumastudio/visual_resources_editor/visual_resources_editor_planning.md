# Visual Resources Editor - Architecture & Refactoring Plan

This document outlines the solutions to address the critical architectural flaws and performance bottlenecks in the Visual Resources Editor. 

---

## 1. State Manager Rescan (The Eager Loading Trap)

**The Problem:** `StateManager.rescan()` loads every single `.tres` file matching your class into memory using `ResourceLoader.load()`. In a project with 1000+ resources, this causes massive CPU spikes, freezes the editor, and hogs memory. Additionally, `ProjectClassScanner.get_class_from_tres_file()` loads every `.tres` file in the project just to check its script class!

**The Solution:** Implement **Lazy Loading**. The State Manager should only store resource paths. We should avoid loading the full resource until the UI actually requests it (e.g., when a row becomes visible).

**Code Implementation:**

Modify `state_manager.gd`:
```gdscript
# Change the data_changed signal to pass paths instead of loaded Resources
signal data_changed(resource_paths: Array[String], columns: Array[Dictionary])

# Instead of loading resources, just get their paths
func rescan() -> void:
	if _current_class_name.is_empty():
		return
	var classes: Array[String] = _get_included_classes()
	var columns: Array[Dictionary] = _compute_union_columns(classes)
	var paths: Array[String] = _get_resource_paths(classes)
	data_changed.emit(paths, columns)

func _get_resource_paths(classes: Array[String]) -> Array[String]:
	var root: EditorFileSystemDirectory = EditorInterface.get_resource_filesystem().get_filesystem()
	# This scanner needs to be optimized to NOT load the resource (see section 4/6)
	var paths: Array[String] = ProjectClassScanner.scan_folder_for_classed_tres(root, classes)
	paths.sort()
	return paths
```

---

## 2. UI Scalability (Virtual Scrolling)

**The Problem:** The `ResourceList` manually instantiates a heavy `ResourceRow` UI scene for every resource. Godot's UI struggles with thousands of complex nodes inside a `VBoxContainer`.

**The Solution:** Use **Virtualization**. Instead of creating 1000 rows for 1000 resources, create only enough rows to fill the screen (e.g., 20 rows). As the user scrolls, update the data in the existing rows instead of creating new ones.

**Code Implementation:**

Create a custom Virtual Scroll script for your list container:
```gdscript
extends ScrollContainer

@export var row_scene: PackedScene
var item_height: float = 32.0 # Fixed height for rows
var item_paths: Array[String] = []
var active_rows: Array[Control] = []

@onready var content_spacer: Control = $ContentSpacer # A generic Control to set scroll height
@onready var visible_container: VBoxContainer = $ContentSpacer/VisibleContainer

func set_items(paths: Array[String]) -> void:
	item_paths = paths
	content_spacer.custom_minimum_size.y = item_paths.size() * item_height
	_update_visible_items()

func _process(_delta: float) -> void:
	_update_visible_items()

func _update_visible_items() -> void:
	if item_paths.is_empty():
		return
		
	var start_idx: int = max(0, int(scroll_vertical / item_height))
	var visible_count: int = int(size.y / item_height) + 2
	var end_idx: int = min(item_paths.size(), start_idx + visible_count)
	
	# Adjust pool size
	while active_rows.size() < visible_count:
		var row = row_scene.instantiate()
		visible_container.add_child(row)
		active_rows.append(row)
		
	# Position the container to simulate scrolling
	visible_container.position.y = start_idx * item_height
	
	# Bind data (Lazy Load happens here!)
	for i in range(visible_count):
		var row = active_rows[i]
		var data_idx = start_idx + i
		if data_idx < item_paths.size():
			row.show()
			var path = item_paths[data_idx]
			# Load the resource ONLY when it's about to be shown
			var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
			row.bind_resource(res)
		else:
			row.hide()
```

---

## 3. Undo/Redo Integration
*Skipped per request. We will rely on Git for now.*

---

## 4. Cache Properties (Severe I/O Abuse)

**The Problem:** `_compute_union_columns` parses `ProjectSettings.get_global_class_list()` and calls `get_script_property_list()` on scripts repeatedly. This causes major UI lag.

**The Solution:** Cache the parsed global classes and the properties per script path in static dictionaries.

**Code Implementation:**

Modify `project_class_scanner.gd`:
```gdscript
static var _cached_script_properties: Dictionary = {}
static var _cached_global_classes: Dictionary = {}

static func get_properties_from_script_path(script_path: String) -> Array[Dictionary]:
	if _cached_script_properties.has(script_path):
		return _cached_script_properties[script_path]
		
	var properties: Array[Dictionary] = []
	if script_path.is_empty(): return properties
	
	var script: GDScript = load(script_path)
	if script == null: return properties
	
	for prop: Dictionary in script.get_script_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR): continue
		if prop.name.begins_with("resource_") or prop.name in ["script"]: continue
		
		properties.append({
			"name": prop.name,
			"type": prop.type,
			"hint": prop.get("hint", PROPERTY_HINT_NONE),
			"hint_string": prop.get("hint_string", ""),
		})
		
	_cached_script_properties[script_path] = properties
	return properties

# Call this when the plugin is disabled or enabled to clear cache
static func clear_cache() -> void:
	_cached_script_properties.clear()
	_cached_global_classes.clear()
```

---

## 5. Why the Current Debounce Is Flawed

**The Problem:** You implemented a `Timer` attached to `_on_filesystem_changed`. 

**Why it's bad:**
1. `EditorFileSystem.filesystem_changed` fires when **any** file in the Godot project is modified.
2. If the user edits a resource property using your plugin UI, the plugin saves the resource to disk.
3. This save triggers `filesystem_changed`.
4. The debounce timer ticks down, then calls `rescan()`.
5. `rescan()` reloads every single resource and completely rebuilds the UI list.
6. **Result:** The user loses their scroll position, input focus, and selection 0.5 seconds after making any edit! The plugin becomes unusable.

**The Solution:**
You must ignore `filesystem_changed` events that were triggered by the plugin itself.

**Code Implementation:**
```gdscript
# In state_manager.gd
var _is_saving_internally: bool = false

func pause_rescans() -> void:
	_is_saving_internally = true

func resume_rescans() -> void:
	_is_saving_internally = false

func _on_filesystem_changed() -> void:
	if _is_saving_internally:
		return # Ignore changes made by our own plugin!
	%RescanDebounceTimer.start()
```
*Note: Make sure your `ResourceCrud` class calls `StateManager.pause_rescans()` before saving, and `resume_rescans()` after saving.*

---

## 6. Improved Architecture (MVC Enforcement)

**The Problem:** The current architecture splits bulk editing between unused proxies and UI logic. The UI handles too much state.

**The Solution:** Strict Model-View-Controller.
- **Model:** `StateManager` holds raw lists (Paths, Filters, Columns).
- **View:** `ResourceList` and `ResourceRow` only display data and emit "intent" signals (`value_changed_intent`).
- **Controller:** A centralized `ResourceCrud` script catches these intents, updates the resource, saves it to disk, and tells the UI "hey, just update this one specific row".

**Flow:**
1. User types "50" in `ResourceRow`'s health field.
2. `ResourceRow` emits `intent_edit_property(resource_path, "health", 50)`.
3. `ResourceCrud` receives it. It pauses `StateManager` rescans. It applies `50` to the resource and calls `ResourceSaver.save()`.
4. `ResourceCrud` tells `StateManager`, "Item updated".
5. `StateManager` emits `single_item_updated(resource_path)`.
6. Only the specific visible row updates its visual state. The rest of the UI stays untouched. No full rescans! Remove `BulkEditProxy` entirely.

---

## 7. Data Filtering Solution

**The Problem:** Filtering UI nodes by using `row.hide()` crashes or lags when thousands of nodes are instantiated.

**The Solution:** Perform filtering purely on the data array (paths) inside the `StateManager`, before it ever reaches the Virtual Scroll UI.

**Code Implementation:**

Modify `state_manager.gd`:
```gdscript
var _all_paths: Array[String] = []
var _filtered_paths: Array[String] = []
var _current_filter_query: String = ""

# Called when rescan completes
func _apply_filter() -> void:
	if _current_filter_query.is_empty():
		_filtered_paths = _all_paths.duplicate()
	else:
		_filtered_paths.clear()
		for path in _all_paths:
			var file_name = path.get_file().get_basename().to_lower()
			if file_name.contains(_current_filter_query.to_lower()):
				_filtered_paths.append(path)
				
	# Emit to the UI so the Virtual Scroll updates
	data_changed.emit(_filtered_paths, _current_columns)

func set_filter_query(query: String) -> void:
	_current_filter_query = query
	_apply_filter() # Fast, doesn't touch the disk!
```
The UI's SearchBar connects to `StateManager.set_filter_query()`. The UI only renders what is inside `_filtered_paths`.