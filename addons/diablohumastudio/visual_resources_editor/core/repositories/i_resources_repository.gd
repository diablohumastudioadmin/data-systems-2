@tool
class_name IResourcesRepository
extends RefCounted

signal resources_reset(resources: Array[Resource])
signal resources_changed(added: Array[Resource], removed: Array[Resource], modified: Array[Resource])

var resources: Array[Resource] = []


func load_resources(class_names: Array[String]) -> void:
	pass


func scan_for_changes() -> void:
	pass
