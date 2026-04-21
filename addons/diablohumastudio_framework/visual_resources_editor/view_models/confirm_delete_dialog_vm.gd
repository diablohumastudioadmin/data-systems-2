@tool
class_name DH_VRE_ConfirmDeleteDialogVM
extends RefCounted

signal pending_deletions_changed(paths: Array[String])

var _resource_repo: DH_VRE_ResourceRepository
var _pending_deletions: Array[String] = []


func _init(p_resource_repo: DH_VRE_ResourceRepository) -> void:
	_resource_repo = p_resource_repo
	_resource_repo.confirmation_needed.connect(_on_confirmation_needed)


func _on_confirmation_needed(paths: Array[String]) -> void:
	_pending_deletions = paths
	pending_deletions_changed.emit(paths)


func get_pending_deletions() -> Array[String]:
	return _pending_deletions


func delete(paths: Array[String]) -> void:
	_resource_repo.delete(paths)
