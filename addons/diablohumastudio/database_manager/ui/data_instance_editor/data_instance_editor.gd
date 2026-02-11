@tool
extends Control

## Inspector-driven data instance editor.
## The Tree is a read-only overview table. Selecting a row inspects the
## actual DataItem Resource in Godot's Inspector, giving native editors
## for every property type with zero custom widget code.

const BulkEditProxyScript = preload("bulk_edit_proxy.gd")

@onready var type_selector: OptionButton = $VBox/Toolbar/TypeSelector
@onready var instance_tree: Tree = $VBox/InstanceTree
@onready var add_instance_btn: Button = $VBox/Toolbar/AddInstanceBtn
@onready var delete_instance_btn: Button = $VBox/Toolbar/DeleteInstanceBtn
@onready var bulk_edit_btn: MenuButton = $VBox/Toolbar/BulkEditBtn
@onready var save_all_btn: Button = $VBox/Toolbar/SaveAllBtn
@onready var refresh_btn: Button = $VBox/Toolbar/RefreshBtn
@onready var status_label: Label = $VBox/StatusBar/StatusLabel

var database_system: DatabaseSystem
var current_type_name: String = ""

## Live references to the actual DataItem Resources (not dictionaries)
var _data_items: Array[DataItem] = []

## Currently inspected single item (null when bulk editing or nothing selected)
var _inspected_item: DataItem = null

## Bulk editing state
var _bulk_proxy: Resource = null
var _is_bulk_editing: bool = false

## Inspector connection tracking
var _inspector_connected: bool = false


# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	if !database_system:
		database_system = DatabaseSystem.new()

	_setup_ui()
	_connect_signals()
	_connect_inspector()
	_refresh_type_selector()


func _exit_tree() -> void:
	_disconnect_inspector()
	_end_bulk_edit()
	_clear_inspected_item()


# --- Setup -------------------------------------------------------------------

func _setup_ui() -> void:
	instance_tree.set_column_titles_visible(true)
	instance_tree.hide_root = true
	instance_tree.select_mode = Tree.SELECT_MULTI
	instance_tree.allow_reselect = true
	bulk_edit_btn.disabled = true


func _connect_signals() -> void:
	type_selector.item_selected.connect(_on_type_selected)
	add_instance_btn.pressed.connect(_on_add_instance_pressed)
	delete_instance_btn.pressed.connect(_on_delete_instance_pressed)
	save_all_btn.pressed.connect(_on_save_all_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	instance_tree.cell_selected.connect(_on_selection_changed)
	instance_tree.multi_selected.connect(func(_item, _col, _sel): _on_selection_changed())
	instance_tree.nothing_selected.connect(_on_nothing_selected)


func _connect_inspector() -> void:
	if _inspector_connected:
		return
	var inspector := EditorInterface.get_inspector()
	if inspector:
		inspector.property_edited.connect(_on_inspector_property_edited)
		_inspector_connected = true


func _disconnect_inspector() -> void:
	if not _inspector_connected:
		return
	var inspector := EditorInterface.get_inspector()
	if inspector and inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.disconnect(_on_inspector_property_edited)
	_inspector_connected = false


# --- Type Selection ----------------------------------------------------------

func _refresh_type_selector() -> void:
	type_selector.clear()
	var types = database_system.type_registry.get_game_type_names()
	for i in range(types.size()):
		type_selector.add_item(types[i], i)

	if types.size() > 0:
		type_selector.selected = 0
		_load_type(types[0])


func _on_type_selected(index: int) -> void:
	var type_name = type_selector.get_item_text(index)
	_load_type(type_name)


func _load_type(type_name: String) -> void:
	current_type_name = type_name
	_end_bulk_edit()
	_clear_inspected_item()

	var type_def = database_system.type_registry.get_type(type_name)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return

	# Column 0 = row index, columns 1..N = properties
	instance_tree.columns = type_def.properties.size() + 1
	instance_tree.set_column_title(0, "#")
	instance_tree.set_column_expand(0, false)
	instance_tree.set_column_custom_minimum_width(0, 50)

	for i in range(type_def.properties.size()):
		var prop = type_def.properties[i]
		instance_tree.set_column_title(i + 1, prop.name)
		instance_tree.set_column_expand(i + 1, true)

	_refresh_instances()


# --- Instance Display (read-only Tree) ---------------------------------------

func _refresh_instances() -> void:
	instance_tree.clear()
	var tree_root = instance_tree.create_item()

	if current_type_name.is_empty():
		return

	var type_def = database_system.type_registry.get_type(current_type_name)
	if type_def == null:
		return

	# Get ACTUAL DataItem resources (not dictionaries)
	_data_items = database_system.get_data_items(current_type_name)

	for idx in range(_data_items.size()):
		var data_item := _data_items[idx]
		var tree_item := instance_tree.create_item(tree_root)

		# Column 0: index label
		tree_item.set_text(0, str(idx))
		tree_item.set_metadata(0, idx)

		# Property columns: display values as text (read-only)
		for i in range(type_def.properties.size()):
			var prop = type_def.properties[i]
			var value = data_item.get(prop.name)
			tree_item.set_text(i + 1, _value_to_display(value, prop.type))

			# Visual hint: show color swatch for Color properties
			if prop.type == DataTypeDefinition.PropertyType.COLOR and value is Color:
				tree_item.set_custom_bg_color(i + 1, value)
				tree_item.set_custom_color(i + 1, Color.BLACK if value.v > 0.5 else Color.WHITE)

	_update_status("%d instances" % _data_items.size())


# --- Selection Handling ------------------------------------------------------

func _on_selection_changed() -> void:
	var selected := _get_selected_tree_items()

	if selected.size() == 1:
		# Single selection: inspect the DataItem in Godot's Inspector
		var idx: int = selected[0].get_metadata(0)
		if idx >= 0 and idx < _data_items.size():
			_end_bulk_edit()
			_inspect_item(_data_items[idx])
			_update_status("Editing instance #%d in Inspector" % idx)
		bulk_edit_btn.disabled = true

	elif selected.size() > 1:
		# Multi-selection: enable bulk edit
		_clear_inspected_item()
		_setup_bulk_edit_menu()
		bulk_edit_btn.disabled = false
		_update_status("%d instances selected - use Bulk Edit" % selected.size())


func _on_nothing_selected() -> void:
	_clear_inspected_item()
	_end_bulk_edit()
	_update_status("%d instances" % _data_items.size())


func _get_selected_tree_items() -> Array[TreeItem]:
	var items: Array[TreeItem] = []
	var item := instance_tree.get_next_selected(null)
	while item:
		items.append(item)
		item = instance_tree.get_next_selected(item)
	return items


# --- Single Instance Inspector Editing ---------------------------------------

func _inspect_item(data_item: DataItem) -> void:
	_clear_inspected_item()
	_inspected_item = data_item
	EditorInterface.inspect_object(data_item)


func _clear_inspected_item() -> void:
	_inspected_item = null


func _on_inspector_property_edited(property: String) -> void:
	# Guard: if we're bulk editing, the proxy handles it
	if _is_bulk_editing:
		return

	# Guard: only react if we have an active inspected item
	if _inspected_item == null:
		return

	# Guard: only react if the property belongs to our type definition
	var type_def = database_system.type_registry.get_type(current_type_name)
	if type_def == null or not type_def.has_property(property):
		return

	# The Inspector already modified the DataItem in-place (it's a Resource).
	# We just need to save and refresh the Tree display.
	database_system.save_instances(current_type_name)
	_refresh_instances()


# --- Bulk Editing ------------------------------------------------------------

func _setup_bulk_edit_menu() -> void:
	var popup := bulk_edit_btn.get_popup()
	popup.clear()

	if popup.id_pressed.is_connected(_on_bulk_edit_property_selected):
		popup.id_pressed.disconnect(_on_bulk_edit_property_selected)

	var type_def = database_system.type_registry.get_type(current_type_name)
	if type_def == null:
		return

	for i in range(type_def.properties.size()):
		popup.add_item(type_def.properties[i].name, i)

	popup.id_pressed.connect(_on_bulk_edit_property_selected)


func _on_bulk_edit_property_selected(id: int) -> void:
	var type_def = database_system.type_registry.get_type(current_type_name)
	if type_def == null or id >= type_def.properties.size():
		return
	_start_bulk_edit(type_def.properties[id])


func _start_bulk_edit(prop: Dictionary) -> void:
	_end_bulk_edit()
	_is_bulk_editing = true

	# Get initial value from first selected item
	var selected := _get_selected_tree_items()
	var initial_value = prop.default
	if selected.size() > 0:
		var idx: int = selected[0].get_metadata(0)
		if idx >= 0 and idx < _data_items.size():
			initial_value = _data_items[idx].get(prop.name)

	# Create proxy Resource with one dynamic property
	_bulk_proxy = BulkEditProxyScript.new()
	_bulk_proxy.setup(prop.name, prop.type, initial_value)
	_bulk_proxy.value_changed.connect(_on_bulk_value_changed)

	# Show in Inspector
	EditorInterface.inspect_object(_bulk_proxy)
	_update_status("Bulk editing '%s' for %d instances" % [prop.name, selected.size()])


func _on_bulk_value_changed(property_name: String, new_value: Variant) -> void:
	var selected := _get_selected_tree_items()
	for tree_item in selected:
		var idx: int = tree_item.get_metadata(0)
		if idx >= 0 and idx < _data_items.size():
			_data_items[idx].set(property_name, new_value)

	# Persist and refresh
	database_system.save_instances(current_type_name)
	_refresh_instances()


func _end_bulk_edit() -> void:
	if _bulk_proxy:
		if _bulk_proxy.value_changed.is_connected(_on_bulk_value_changed):
			_bulk_proxy.value_changed.disconnect(_on_bulk_value_changed)
		_bulk_proxy = null
	_is_bulk_editing = false
	bulk_edit_btn.disabled = true


# --- CRUD Operations --------------------------------------------------------

func _on_add_instance_pressed() -> void:
	if current_type_name.is_empty():
		return
	var instance_data: Dictionary = database_system.create_default_instance(current_type_name)
	database_system.add_instance(current_type_name, instance_data)
	_refresh_instances()
	_update_status("Added new instance")


func _on_delete_instance_pressed() -> void:
	var selected := _get_selected_tree_items()
	if selected.is_empty():
		return

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Delete %d instance(s)?\nThis cannot be undone." % selected.size()
	confirm.confirmed.connect(func():
		# Collect indices and delete in reverse order (highest first)
		var indices: Array[int] = []
		for item in selected:
			indices.append(item.get_metadata(0))
		indices.sort()
		indices.reverse()

		for idx in indices:
			database_system.remove_instance(current_type_name, idx)

		_clear_inspected_item()
		_end_bulk_edit()
		_refresh_instances()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _on_save_all_pressed() -> void:
	if not current_type_name.is_empty():
		database_system.save_instances(current_type_name)
		_update_status("Saved all instances")


func _on_refresh_pressed() -> void:
	if not current_type_name.is_empty():
		database_system.load_instances(current_type_name)
		_refresh_instances()
		_update_status("Refreshed from disk")


# --- Display Helpers ---------------------------------------------------------

func _value_to_display(value: Variant, prop_type: DataTypeDefinition.PropertyType) -> String:
	if value == null:
		return "<null>"
	match prop_type:
		DataTypeDefinition.PropertyType.BOOL:
			return "true" if value else "false"
		DataTypeDefinition.PropertyType.TEXTURE2D:
			if value is Texture2D:
				return value.resource_path.get_file()
			return str(value)
		DataTypeDefinition.PropertyType.VECTOR2:
			if value is Vector2:
				return "(%g, %g)" % [value.x, value.y]
			return str(value)
		DataTypeDefinition.PropertyType.VECTOR3:
			if value is Vector3:
				return "(%g, %g, %g)" % [value.x, value.y, value.z]
			return str(value)
		DataTypeDefinition.PropertyType.COLOR:
			if value is Color:
				return value.to_html()
			return str(value)
		_:
			return str(value)


func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message
