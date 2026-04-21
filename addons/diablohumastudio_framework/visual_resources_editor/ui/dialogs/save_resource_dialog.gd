@tool
class_name DH_VRE_SaveResourceDialog
extends EditorFileDialog

var vm: DH_VRE_SaveResourceDialogVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	filters = PackedStringArray(["*.tres"])
	file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_selected.connect(_on_file_selected)
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.show_requested.connect(_on_show_requested)


func _on_show_requested() -> void:
	var class_name_: String = vm.get_class_to_create()
	if class_name_.is_empty():
		return
	if vm.get_class_script_path(class_name_).is_empty():
		return
	title = "Save New %s" % class_name_
	popup_centered(Vector2i(800, 500))


func _on_file_selected(path: String) -> void:
	var class_name_: String = vm.get_class_to_create()
	vm.create_resource(class_name_, path)
