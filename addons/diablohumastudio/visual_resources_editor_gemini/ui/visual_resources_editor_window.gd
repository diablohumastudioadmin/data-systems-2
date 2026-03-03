@tool
class_name VREGVisualResourcesEditorWindow
extends Window

const VREGVisualDataInstanceRow = preload("res://addons/diablohumastudio/visual_resources_editor_gemini/ui/visual_data_instance_row.tscn")

@onready var class_selector: OptionButton = $VBoxContainer/Toolbar/ClassSelector
@onready var create_button: Button = $VBoxContainer/Toolbar/CreateButton
@onready var bulk_edit_button: Button = $VBoxContainer/Toolbar/BulkEditButton
@onready var rows_container: VBoxContainer = $VBoxContainer/ScrollContainer/RowsContainer
@onready var file_dialog: FileDialog = $FileDialog

var _bulk_edit_proxy: VREGBulkEditProxy

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
		
	# Setup FileDialog
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.add_filter("*.tres, *.res", "Resource Files")
	file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	
	_populate_class_selector()
	
	class_selector.item_selected.connect(_on_class_selected)
	create_button.pressed.connect(_on_create_button_pressed)
	bulk_edit_button.pressed.connect(_on_bulk_edit_button_pressed)

func _populate_class_selector() -> void:
	class_selector.clear()
	var classes = VREGResourceScanner.get_resource_classes()
	for i in range(classes.size()):
		var c = classes[i]
		class_selector.add_item(c.get("class", ""))
		class_selector.set_item_metadata(i, {
			"class": c.get("class", ""),
			"path": c.get("path", "")
		})
	
	if class_selector.item_count > 0:
		_refresh_list()

func _on_class_selected(_index: int) -> void:
	_refresh_list()

func _refresh_list() -> void:
	for child in rows_container.get_children():
		child.queue_free()
		
	var idx = class_selector.selected
	if idx < 0:
		return
		
	var meta = class_selector.get_item_metadata(idx)
	var target_class_name = meta.get("class", "")
	var script_path = meta.get("path", "")
	
	var resource_paths = VREGResourceScanner.find_resources_of_type(target_class_name, script_path)
	
	for path in resource_paths:
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res:
			var row_inst = VREGVisualDataInstanceRow.instantiate()
			rows_container.add_child(row_inst)
			row_inst.setup(res, path)
			row_inst.delete_requested.connect(_on_row_delete_requested)
			row_inst.edit_requested.connect(_on_row_edit_requested)
			row_inst.selection_changed.connect(_on_row_selection_changed)
			
	_update_bulk_edit_button_state()

func _on_row_delete_requested(row: VREGVisualDataInstanceRow) -> void:
	var path = row.get_file_path()
	var dir = DirAccess.open("res://")
	if dir and dir.file_exists(path):
		var err = dir.remove(path)
		if err == OK:
			row.queue_free()
			EditorInterface.get_resource_filesystem().scan()
			print("Deleted: ", path)
		else:
			push_error("Failed to delete: ", path)
			
	_update_bulk_edit_button_state()

func _on_row_edit_requested(resource: Resource) -> void:
	EditorInterface.edit_resource(resource)

func _on_row_selection_changed(_row: VREGVisualDataInstanceRow, _selected: bool) -> void:
	_update_bulk_edit_button_state()

func _update_bulk_edit_button_state() -> void:
	var selected_count = _get_selected_rows().size()
	bulk_edit_button.disabled = selected_count < 2

func _get_selected_rows() -> Array[VREGVisualDataInstanceRow]:
	var selected: Array[VREGVisualDataInstanceRow] = []
	for child in rows_container.get_children():
		if child is VREGVisualDataInstanceRow and child.is_selected():
			selected.append(child)
	return selected

func _on_create_button_pressed() -> void:
	file_dialog.popup_centered_ratio(0.5)

func _on_file_dialog_file_selected(path: String) -> void:
	var idx = class_selector.selected
	if idx < 0:
		return
		
	var meta = class_selector.get_item_metadata(idx)
	var target_class_name = meta.get("class", "")
	var script_path = meta.get("path", "")
	
	var res: Resource
	if script_path != "":
		var script = load(script_path)
		if script:
			res = script.new()
	elif ClassDB.class_exists(target_class_name):
		res = ClassDB.instantiate(target_class_name)
		
	if res:
		var err = ResourceSaver.save(res, path)
		if err == OK:
			EditorInterface.get_resource_filesystem().scan()
			_refresh_list()
			print("Created new instance: ", path)
		else:
			push_error("Failed to save new resource at: ", path)
	else:
		push_error("Failed to instantiate class: ", target_class_name)

func _on_bulk_edit_button_pressed() -> void:
	var selected_rows = _get_selected_rows()
	if selected_rows.size() < 2:
		return
		
	var idx = class_selector.selected
	var meta = class_selector.get_item_metadata(idx)
	var target_class_name = meta.get("class", "")
	var script_path = meta.get("path", "")
	
	_bulk_edit_proxy = VREGBulkEditProxy.new()
	_bulk_edit_proxy.setup(target_class_name, script_path)
	
	# Connect to proxy changes
	_bulk_edit_proxy.property_value_changed.connect(func(prop_name: String, value: Variant):
		for row in selected_rows:
			var res = row.get_resource()
			if res:
				res.set(prop_name, value)
				ResourceSaver.save(res, row.get_file_path())
		print("Bulk updated '", prop_name, "' for ", selected_rows.size(), " items.")
	)
	
	EditorInterface.edit_resource(_bulk_edit_proxy)

func _on_close_requested() -> void:
	hide()
	queue_free()
