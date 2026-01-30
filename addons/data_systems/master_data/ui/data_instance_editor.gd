@tool
extends Control

## Table-based editor for data instances
## Allows spreadsheet-style editing with bulk operations

@onready var type_selector: OptionButton = $VBox/Toolbar/TypeSelector
@onready var instance_tree: Tree = $VBox/InstanceTree
@onready var add_instance_btn: Button = $VBox/Toolbar/AddInstanceBtn
@onready var delete_instance_btn: Button = $VBox/Toolbar/DeleteInstanceBtn
@onready var save_btn: Button = $VBox/Toolbar/SaveBtn
@onready var refresh_btn: Button = $VBox/Toolbar/RefreshBtn

var master_data_system: MasterDataSystem
var current_type_name: String = ""
var tree_root: TreeItem


func _ready() -> void:
	if !master_data_system:
		master_data_system = MasterDataSystem.new()

	_setup_ui()
	_connect_signals()
	_refresh_type_selector()


func _setup_ui() -> void:
	# Setup tree
	instance_tree.set_column_titles_visible(true)
	instance_tree.hide_root = true
	tree_root = instance_tree.create_item()


func _connect_signals() -> void:
	type_selector.item_selected.connect(_on_type_selected)
	add_instance_btn.pressed.connect(_on_add_instance_pressed)
	delete_instance_btn.pressed.connect(_on_delete_instance_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	instance_tree.item_edited.connect(_on_tree_item_edited)


func _refresh_type_selector() -> void:
	type_selector.clear()

	var types = master_data_system.type_registry.get_master_type_names()
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

	var type_def = master_data_system.type_registry.get_type(type_name)
	if type_def == null:
		push_error("Type not found: %s" % type_name)
		return

	# Setup columns
	instance_tree.columns = type_def.properties.size()
	for i in range(type_def.properties.size()):
		var prop = type_def.properties[i]
		instance_tree.set_column_title(i, prop.name)
		instance_tree.set_column_expand(i, true)

	# Load instances
	_refresh_instances()


func _refresh_instances() -> void:
	# Clear tree
	instance_tree.clear()
	tree_root = instance_tree.create_item()

	if current_type_name.is_empty():
		return

	var type_def = master_data_system.type_registry.get_type(current_type_name)
	if type_def == null:
		return

	var instances = master_data_system.get_instances(current_type_name)

	for instance in instances:
		var item = instance_tree.create_item(tree_root)

		for i in range(type_def.properties.size()):
			var prop = type_def.properties[i]
			var value = instance.get(prop.name, prop.default)

			# Set cell value and make it editable
			item.set_text(i, _value_to_string(value, prop.type))
			item.set_editable(i, true)
			item.set_metadata(i, {"property": prop.name, "type": prop.type})


func _on_add_instance_pressed() -> void:
	if current_type_name.is_empty():
		return

	# Create default instance
	var instance = master_data_system.create_default_instance(current_type_name)
	master_data_system.add_instance(current_type_name, instance)
	_refresh_instances()


func _on_delete_instance_pressed() -> void:
	var selected = instance_tree.get_selected()
	if !selected:
		return

	var index = selected.get_index()

	# Confirm deletion
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Delete this instance?\nThis cannot be undone."
	confirm.confirmed.connect(func():
		master_data_system.remove_instance(current_type_name, index)
		_refresh_instances()
		confirm.queue_free()
	)
	confirm.canceled.connect(func(): confirm.queue_free())

	add_child(confirm)
	confirm.popup_centered()


func _on_save_pressed() -> void:
	# Save current edits
	_save_current_edits()

	# Save to disk
	if !current_type_name.is_empty():
		master_data_system.save_instances(current_type_name)
		_show_message("Saved successfully!")


func _on_refresh_pressed() -> void:
	if !current_type_name.is_empty():
		master_data_system.load_instances(current_type_name)
		_refresh_instances()


func _on_tree_item_edited() -> void:
	# Auto-save on edit (optional)
	# For now, just mark as dirty
	pass


func _save_current_edits() -> void:
	if current_type_name.is_empty():
		return

	var type_def = master_data_system.type_registry.get_type(current_type_name)
	if type_def == null:
		return

	# Read all instances from tree
	var new_instances: Array = []
	var item = tree_root.get_first_child()

	while item:
		var instance = {}

		for i in range(type_def.properties.size()):
			var prop = type_def.properties[i]
			var text = item.get_text(i)
			var value = _string_to_value(text, prop.type)
			instance[prop.name] = value

		new_instances.append(instance)
		item = item.get_next()

	# Update data system
	master_data_system.data_instances[current_type_name] = new_instances


func _value_to_string(value: Variant, prop_type: DataTypeDefinition.PropertyType) -> String:
	match prop_type:
		DataTypeDefinition.PropertyType.INT, DataTypeDefinition.PropertyType.FLOAT:
			return str(value)
		DataTypeDefinition.PropertyType.STRING:
			return value
		DataTypeDefinition.PropertyType.BOOL:
			return "true" if value else "false"
		DataTypeDefinition.PropertyType.TEXTURE2D:
			if value is Texture2D:
				return value.resource_path
			return str(value)
		DataTypeDefinition.PropertyType.VECTOR2:
			if value is Vector2:
				return "%f, %f" % [value.x, value.y]
			return str(value)
		DataTypeDefinition.PropertyType.VECTOR3:
			if value is Vector3:
				return "%f, %f, %f" % [value.x, value.y, value.z]
			return str(value)
		DataTypeDefinition.PropertyType.COLOR:
			if value is Color:
				return value.to_html()
			return str(value)
		_:
			return str(value)


func _string_to_value(text: String, prop_type: DataTypeDefinition.PropertyType) -> Variant:
	match prop_type:
		DataTypeDefinition.PropertyType.INT:
			return int(text)
		DataTypeDefinition.PropertyType.FLOAT:
			return float(text)
		DataTypeDefinition.PropertyType.STRING:
			return text
		DataTypeDefinition.PropertyType.BOOL:
			return text.to_lower() == "true"
		DataTypeDefinition.PropertyType.TEXTURE2D:
			if text.is_empty():
				return null
			if ResourceLoader.exists(text):
				return load(text)
			return text
		DataTypeDefinition.PropertyType.VECTOR2:
			var parts = text.split(",")
			if parts.size() >= 2:
				return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
			return Vector2.ZERO
		DataTypeDefinition.PropertyType.VECTOR3:
			var parts = text.split(",")
			if parts.size() >= 3:
				return Vector3(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
			return Vector3.ZERO
		DataTypeDefinition.PropertyType.COLOR:
			return Color.html(text)
		_:
			return text


func _show_message(message: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.confirmed.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered_ratio(0.3)
