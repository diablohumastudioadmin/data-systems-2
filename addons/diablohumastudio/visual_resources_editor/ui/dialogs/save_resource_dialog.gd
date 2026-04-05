@tool
class_name SaveResourceDialog
extends EditorFileDialog

var vm: SaveResourceDialogVM = null:
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
	var script_path: String = vm.get_class_script_path(class_name_)
	var script: GDScript = load(script_path)
	if script == null:
		vm.report_error("Failed to load script for %s." % class_name_)
		return
	if not script.can_instantiate():
		vm.report_error("Can't instantiate %s.\nCheck its constructor." % class_name_)
		return
	var instance: Resource = script.new()
	var err: Error = ResourceSaver.save(instance, path)
	if err != OK:
		vm.report_error("Failed to save resource:\n%s" % path)
