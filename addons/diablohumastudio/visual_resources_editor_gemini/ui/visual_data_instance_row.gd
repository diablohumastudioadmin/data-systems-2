@tool
class_name VREGVisualDataInstanceRow
extends HBoxContainer

signal delete_requested(row: VREGVisualDataInstanceRow)
signal edit_requested(resource: Resource)
signal selection_changed(row: VREGVisualDataInstanceRow, selected: bool)

@onready var checkbox: CheckBox = $CheckBox
@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var path_label: Label = $VBoxContainer/PathLabel
@onready var edit_button: Button = $ActionBox/EditButton
@onready var delete_button: Button = $ActionBox/DeleteButton

var _resource: Resource
var _file_path: String

func setup(resource: Resource, file_path: String) -> void:
	_resource = resource
	_file_path = file_path
	
	if not is_inside_tree():
		await ready
		
	var res_name = file_path.get_file().get_basename()
	name_label.text = res_name
	path_label.text = file_path
	
	checkbox.toggled.connect(func(toggled_on: bool):
		selection_changed.emit(self, toggled_on)
	)
	
	edit_button.pressed.connect(func():
		edit_requested.emit(_resource)
	)
	
	delete_button.pressed.connect(func():
		delete_requested.emit(self)
	)

func get_resource() -> Resource:
	return _resource

func get_file_path() -> String:
	return _file_path

func is_selected() -> bool:
	return checkbox.button_pressed

func set_selected(selected: bool) -> void:
	checkbox.button_pressed = selected
