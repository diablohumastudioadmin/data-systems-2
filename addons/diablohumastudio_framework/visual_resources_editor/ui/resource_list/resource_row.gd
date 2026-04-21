@tool
class_name DH_VRE_ResourceRow
extends Button

const RESOURCE_FIELD_LABEL_SCENE: PackedScene = preload("uid://uru49vi0kvgxy")
const FIELD_SEPARATOR_SCENE: PackedScene = preload("uid://y2kj6h91hm8r6")

var vm: DH_VRE_ResourceRowVM = null
var current_shared_property_list: Array[DH_VRE_ResourceProperty] = []
var _prop_labels: Dictionary = {}


func _ready() -> void:
	if not vm: return
	vm.is_selected_changed.connect(set_selected)
	%FileNameLabel.text = vm.resource.resource_path.get_file()
	%FileNameLabel.tooltip_text = vm.resource.resource_path
	_build_field_labels()
	set_selected(vm.is_selected())


func _build_field_labels() -> void:
	for child: Node in %FieldsContainer.get_children():
		child.queue_free()
	_prop_labels.clear()

	var owned: Dictionary = {}
	if vm.resource and vm.resource.get_script():
		for p: Dictionary in vm.resource.get_script().get_script_property_list():
			if not (p.usage & PROPERTY_USAGE_EDITOR):
				continue
			var pname: String = p.name
			if pname.begins_with("resource_") or pname.begins_with("metadata/"):
				continue
			if pname in ["script", "resource_local_to_scene"]:
				continue
			owned[pname] = true

	for i: int in current_shared_property_list.size():
		if i > 0:
			var sep: VSeparator = FIELD_SEPARATOR_SCENE.instantiate()
			%FieldsContainer.add_child(sep)

		var label: DH_VRE_ResourceFieldLabel = RESOURCE_FIELD_LABEL_SCENE.instantiate()
		var col_name: String = current_shared_property_list[i].name
		if owned.has(col_name):
			_prop_labels[col_name] = label
			label.set_value(vm.resource, current_shared_property_list[i])
		%FieldsContainer.add_child(label)


func rebuild_fields() -> void:
	_build_field_labels()


func update_display() -> void:
	if not vm: return
	for col: DH_VRE_ResourceProperty in current_shared_property_list:
		if _prop_labels.has(col.name):
			_prop_labels[col.name].set_value(vm.resource, col)


func set_selected(selected: bool) -> void:
	button_pressed = selected


func get_resource_path() -> String:
	return vm.resource.resource_path


func _on_pressed() -> void:
	var ctrl_held: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	vm.select(ctrl_held, shift_held)


func _on_delete_pressed() -> void:
	vm.request_delete()
