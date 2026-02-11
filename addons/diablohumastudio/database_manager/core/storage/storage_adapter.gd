@tool
class_name StorageAdapter
extends RefCounted

## Abstract interface for data persistence
## Currently only ResourceStorageAdapter, but extensible for future backends

## Load all instances for a data type
## Returns typed array of DataItem resources
func load_instances(type_name: String) -> Array[DataItem]:
	push_error("StorageAdapter.load_instances() must be overridden")
	var empty: Array[DataItem] = []
	return empty

## Save all instances for a data type
func save_instances(type_name: String, instances: Array[DataItem]) -> Error:
	push_error("StorageAdapter.save_instances() must be overridden")
	return ERR_UNAVAILABLE

## Check if data file exists for type
func has_data(type_name: String) -> bool:
	push_error("StorageAdapter.has_data() must be overridden")
	return false

## Delete data file for type
func delete_data(type_name: String) -> Error:
	push_error("StorageAdapter.delete_data() must be overridden")
	return ERR_UNAVAILABLE

## Get file path (for debugging)
func get_data_path(type_name: String) -> String:
	return ""
