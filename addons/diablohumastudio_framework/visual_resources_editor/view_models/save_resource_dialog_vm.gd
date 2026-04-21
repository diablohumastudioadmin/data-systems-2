@tool
class_name DH_VRE_SaveResourceDialogVM
extends RefCounted

signal class_to_create_changed(class_name_: String)
signal show_requested()

var _resource_repo: DH_VRE_ResourceRepository


func _init(p_resource_repo: DH_VRE_ResourceRepository, toolbar_vm: DH_VRE_ToolbarVM) -> void:
	_resource_repo = p_resource_repo
	_resource_repo.selected_class_changed.connect(
		func(class_name_: String): class_to_create_changed.emit(class_name_))
	toolbar_vm.create_requested.connect(func(): show_requested.emit())


func get_class_to_create() -> String:
	return _resource_repo.selected_class


func get_class_script_path(class_name_: String) -> String:
	return _resource_repo.class_registry.get_script_path_from_class_name(class_name_)


func create_resource(class_name_: String, path: String) -> void:
	var script: GDScript = _resource_repo.class_registry.get_script_from_class_name(class_name_)
	_resource_repo.create(script, path)
