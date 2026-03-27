@tool
class_name StubResourcesRepository
extends IResourcesRepository


func load_resources(_class_names: Array[String]) -> void:
	resources_reset.emit(resources)


func scan_for_changes() -> void:
	pass
