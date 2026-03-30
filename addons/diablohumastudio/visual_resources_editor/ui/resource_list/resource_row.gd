@tool
class_name ResourceRow
extends Button

signal resource_row_selected(resource: Resource, ctrl_held: bool, shift_held: bool)

const RESOURCE_FIELD_LABEL_SCENE: PackedScene = preload("uid://uru49vi0kvgxy")
const FIELD_SEPARATOR_SCENE: PackedScene = preload("uid://y2kj6h91hm8r6")

var resource: Resource = null
var current_shared_propery_list: Array[ResourceProperty] = []
var _prop_labels: Dictionary = {}  # property_name → ResourceFieldLabel (only for properties this resource owns)


func _ready() -> void:
	if not resource: return

	%FileNameLabel.text = resource.resource_path.get_file()
	%FileNameLabel.tooltip_text = resource.resource_path

	_build_field_labels()


func _build_field_labels() -> void:
	for child: Node in %FieldsContainer.get_children():
		child.queue_free()
	_prop_labels.clear()

	# Map which editor-visible properties this resource's script actually declares
	# Uses the same filter as ProjectClassScanner.get_properties_from_script_path()
	var owned: Dictionary = {}
	if resource and resource.get_script():
		for p: Dictionary in resource.get_script().get_script_property_list():
			if not (p.usage & PROPERTY_USAGE_EDITOR):
				continue
			var pname: String = p.name
			if pname.begins_with("resource_") or pname.begins_with("metadata/"):
				continue
			if pname in ["script", "resource_local_to_scene"]:
				continue
			owned[pname] = true

	for i: int in current_shared_propery_list.size():
		if i > 0:
			var sep: VSeparator = FIELD_SEPARATOR_SCENE.instantiate()
			%FieldsContainer.add_child(sep)

		var label: ResourceFieldLabel = RESOURCE_FIELD_LABEL_SCENE.instantiate()

		var col_name: String = current_shared_propery_list[i].name
		if owned.has(col_name):
			_prop_labels[col_name] = label
			label.set_value(resource, current_shared_propery_list[i])
		# else: label stays blank — belongs to a sibling subclass

		%FieldsContainer.add_child(label)


func update_display() -> void:
	if not resource:
		return
	for col: ResourceProperty in current_shared_propery_list:
		if _prop_labels.has(col.name):
			_prop_labels[col.name].set_value(resource, col)


func is_selected() -> bool:
	return button_pressed


func set_selected(selected: bool) -> void:
	button_pressed = selected


func get_resource() -> Resource:
	return resource


func get_resource_path() -> String:
	return resource.resource_path


func _on_pressed() -> void:
	var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	resource_row_selected.emit(resource, ctrl_held, shift_held)


func _on_delete_pressed() -> void:
	if resource == null:
		return
	%ConfirmDeleteDialog.dialog_text = "Move to trash?\n\n%s" % resource.resource_path.get_file()
	%ConfirmDeleteDialog.popup_centered()


func _on_delete_confirmed() -> void:
	if resource == null:
		return
	var path: String = resource.resource_path
	if not path.begins_with("res://"):
		push_warning("VRE: Skipping delete of path outside project: %s" % path)
		return
	var err: Error = OS.move_to_trash(ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("VRE: Failed to delete: %s" % path)
		return
	EditorInterface.get_resource_filesystem().update_file(path)
