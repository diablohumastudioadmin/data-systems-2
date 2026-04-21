@tool
class_name DH_VRE_SubclassFilterVM
extends RefCounted

signal include_subclasses_changed(include: bool)

var _resource_repo: DH_VRE_ResourceRepository


func _init(p_resource_repo: DH_VRE_ResourceRepository) -> void:
	_resource_repo = p_resource_repo
	_resource_repo.include_subclasses_changed.connect(
		func(include: bool): include_subclasses_changed.emit(include))


func get_include_subclasses() -> bool:
	return _resource_repo.include_subclasses


func set_include_subclasses(include: bool) -> void:
	_resource_repo.include_subclasses = include
