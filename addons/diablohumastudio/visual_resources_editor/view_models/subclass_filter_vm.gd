@tool
class_name SubclassFilterVM
extends RefCounted

signal include_subclasses_changed(include: bool)

var _session: SessionStateModel


func _init(p_session: SessionStateModel) -> void:
	_session = p_session
	_session.include_subclasses_changed.connect(
		func(include: bool): include_subclasses_changed.emit(include))


func get_include_subclasses() -> bool:
	return _session.include_subclasses


func set_include_subclasses(include: bool) -> void:
	_session.include_subclasses = include
