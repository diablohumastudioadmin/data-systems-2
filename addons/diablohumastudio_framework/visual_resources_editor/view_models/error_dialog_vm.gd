@tool
class_name DH_VRE_ErrorDialogVM
extends RefCounted

signal error_occurred(message: String)


func _init(resource_repo: DH_VRE_ResourceRepository) -> void:
	resource_repo.error_occurred.connect(func(msg: String): error_occurred.emit(msg))
