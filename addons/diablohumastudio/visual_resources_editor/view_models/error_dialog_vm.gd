@tool
class_name ErrorDialogVM
extends RefCounted

signal error_occurred(message: String)


func _init(resource_repo: ResourceRepository) -> void:
	resource_repo.error_occurred.connect(func(msg: String): error_occurred.emit(msg))
