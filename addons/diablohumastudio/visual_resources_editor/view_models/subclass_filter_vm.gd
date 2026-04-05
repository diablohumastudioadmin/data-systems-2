@tool
class_name SubclassFilterVM
extends RefCounted

signal include_subclasses_changed(include: bool)

var _model: VREModel

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.session.include_subclasses_changed.connect(func(include: bool): include_subclasses_changed.emit(include))

func get_include_subclasses() -> bool:
	return _model.session.include_subclasses

func set_include_subclasses(include: bool) -> void:
	_model.session.include_subclasses = include
