@tool
class_name ErrorDialogVM
extends RefCounted

signal error_occurred(message: String)

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.error_occurred.connect(func(msg: String): error_occurred.emit(msg))
