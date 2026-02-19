@tool
extends Control

## Inspector-driven data instance editor.
## The Tree is a read-only overview table. Selecting a row inspects the
## actual DataItem Resource in Godot's Inspector, giving native editors
## for every property type with zero custom widget code.

const BulkEditProxyScript = preload("bulk_edit_proxy.gd")

@onready var table_selector: OptionButton = $VBox/Toolbar/TableSelector
@onready var instance_tree: Tree = $VBox/InstanceTree
@onready var add_instance_btn: Button = $VBox/Toolbar/AddInstanceBtn
@onready var delete_instance_btn: Button = $VBox/Toolbar/DeleteInstanceBtn
@onready var bulk_edit_btn: MenuButton = $VBox/Toolbar/BulkEditBtn
@onready var save_all_btn: Button = $VBox/Toolbar/SaveAllBtn
@onready var refresh_btn: Button = $VBox/Toolbar/RefreshBtn
@onready var status_label: Label = $VBox/StatusBar/StatusLabel

var database_manager: DatabaseManager: set = _set_database_manager
var current_table_name: String = ""

## Live references to the actual DataItem Resources (not dictionaries)
var _data_items: Array[DataItem] = []

## Currently inspected single item (null when bulk editing or nothing selected)
var _inspected_item: DataItem = null

## Bulk editing state
var _bulk_proxy: Resource = null
var _is_bulk_editing: bool = false

## Inspector connection tracking
var _inspector_connected: bool = false
var _initialized: bool = false


# --- Lifecycle ---------------------------------------------------------------

func _set_database_manager(value: DatabaseManager) -> void:
	database_manager = value
	if value and is_node_ready() and not _initialized:
		_initialize()


func _ready() -> void:
	if not database_manager:
		return
	_initialize()


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_setup_ui()
	_connect_signals()
	_connect_inspector()
	_refresh_table_selector()


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
	table_selector.item_selected.connect(_on_table_selected)
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


# --- Public API --------------------------------------------------------------

## Reload table list and instances (called when tables change)
func reload() -> void:
	_refresh_table_selector()


# --- Table Selection ---------------------------------------------------------

func _refresh_table_selector() -> void:
	table_selector.clear()
	var tables = database_manager.get_table_names()
	for i in range(tables.size()):
		table_selector.add_item(tables[i], i)

	if tables.size() > 0:
		table_selector.selected = 0
		_load_table(tables[0])


func _on_table_selected(index: int) -> void:
	var table_name = table_selector.get_item_text(index)
	_load_table(table_name)


func _load_table(table_name: String) -> void:
	current_table_name = table_name
	_end_bulk_edit()
	_clear_inspected_item()

	var properties = database_manager.get_table_properties(table_name)

	# Columns: # | ID | Name | <custom properties...>
	instance_tree.columns = properties.size() + 3
	instance_tree.set_column_title(0, "#")
	instance_tree.set_column_expand(0, false)
	instance_tree.set_column_custom_minimum_width(0, 50)

	instance_tree.set_column_title(1, "ID")
	instance_tree.set_column_expand(1, false)
	instance_tree.set_column_custom_minimum_width(1, 50)

	instance_tree.set_column_title(2, "Name")
	instance_tree.set_column_expand(2, true)

	for i in range(properties.size()):
		instance_tree.set_column_title(i + 3, properties[i].name)
		instance_tree.set_column_expand(i + 3, true)

	_refresh_instances()


# --- Instance Display (read-only Tree) ---------------------------------------

func _refresh_instances() -> void:
	instance_tree.clear()
	var tree_root = instance_tree.create_item()

	if current_table_name.is_empty():
		return

	var properties = database_manager.get_table_properties(current_table_name)
	_data_items = database_manager.get_data_items(current_table_name)

	for idx in range(_data_items.size()):
		var data_item := _data_items[idx]
		var tree_item := instance_tree.create_item(tree_root)

		# Column 0: array index
		tree_item.set_text(0, str(idx))
		tree_item.set_metadata(0, idx)

		# Column 1: stable ID
		tree_item.set_text(1, str(data_item.id))

		# Column 2: name
		tree_item.set_text(2, data_item.name)

		# Property columns: display values as text (read-only)
		for i in range(properties.size()):
			var prop = properties[i]
			var value = data_item.get(prop.name)
			tree_item.set_text(i + 3, _value_to_display(value, prop.type))

			# Visual hint: show color swatch for Color properties
			if prop.type == TYPE_COLOR and value is Color:
				tree_item.set_custom_bg_color(i + 3, value)
				tree_item.set_custom_color(i + 3, Color.BLACK if value.v > 0.5 else Color.WHITE)

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
	# Bring focus to the Inspector dock so the user notices the change
	var inspector := EditorInterface.get_inspector()
	if inspector:
		inspector.grab_focus()


func _clear_inspected_item() -> void:
	_inspected_item = null


func _on_inspector_property_edited(property: String) -> void:
	if _is_bulk_editing:
		return
	if _inspected_item == null:
		return
	# Accept base DataItem properties (name) and custom table properties
	if property != "name" and not database_manager.table_has_property(current_table_name, property):
		return

	# The Inspector already modified the DataItem in-place (it's a Resource).
	# We just need to save and refresh the Tree display.
	database_manager.save_instances(current_table_name)
	_refresh_instances()


# --- Bulk Editing ------------------------------------------------------------

func _setup_bulk_edit_menu() -> void:
	var popup := bulk_edit_btn.get_popup()
	popup.clear()

	if popup.id_pressed.is_connected(_on_bulk_edit_property_selected):
		popup.id_pressed.disconnect(_on_bulk_edit_property_selected)

	var properties = database_manager.get_table_properties(current_table_name)
	for i in range(properties.size()):
		popup.add_item(properties[i].name, i)

	popup.id_pressed.connect(_on_bulk_edit_property_selected)


func _on_bulk_edit_property_selected(id: int) -> void:
	var properties = database_manager.get_table_properties(current_table_name)
	if id >= properties.size():
		return
	_start_bulk_edit(properties[id])


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
	_bulk_proxy.setup(prop.name, prop.type, initial_value, prop.hint, prop.hint_string)
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
	database_manager.save_instances(current_table_name)
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
	if current_table_name.is_empty():
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "New Instance"

	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "Instance name:"
	vbox.add_child(label)
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "e.g. Forest, Desert, Sword..."
	vbox.add_child(line_edit)
	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var instance_name := line_edit.text.strip_edges()
		if instance_name.is_empty():
			dialog.queue_free()
			return
		database_manager.add_instance(current_table_name, instance_name)
		_refresh_instances()
		_update_status("Added instance: %s" % instance_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(300, 100))
	line_edit.grab_focus()


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
			database_manager.remove_instance(current_table_name, idx)

		_clear_inspected_item()
		_end_bulk_edit()
		_refresh_instances()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _on_save_all_pressed() -> void:
	if not current_table_name.is_empty():
		database_manager.save_instances(current_table_name)
		_update_status("Saved all instances")


func _on_refresh_pressed() -> void:
	if not current_table_name.is_empty():
		database_manager.load_instances(current_table_name)
		_refresh_instances()
		_update_status("Refreshed from disk")


# --- Display Helpers ---------------------------------------------------------

func _value_to_display(value: Variant, prop_type: int) -> String:
	if value == null:
		return "<null>"
	match prop_type:
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_OBJECT:
			if value is Texture2D:
				return value.resource_path.get_file()
			return str(value)
		TYPE_VECTOR2:
			if value is Vector2:
				return "(%g, %g)" % [value.x, value.y]
			return str(value)
		TYPE_VECTOR3:
			if value is Vector3:
				return "(%g, %g, %g)" % [value.x, value.y, value.z]
			return str(value)
		TYPE_COLOR:
			if value is Color:
				return value.to_html()
			return str(value)
		_:
			return str(value)


func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message
