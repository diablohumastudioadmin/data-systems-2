@tool
class_name StorageAdapter
extends RefCounted

## Abstract interface for per-instance database persistence.
## Override all methods in subclasses.

## Save a single DataItem to its own .tres file
func save_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	push_error("StorageAdapter.save_instance() must be overridden")
	return ERR_UNAVAILABLE

## Load all DataItem instances for a table from disk
func load_instances(table_name: String, base_path: String) -> Array[DataItem]:
	push_error("StorageAdapter.load_instances() must be overridden")
	return []

## Delete a single DataItem's .tres file from disk
func delete_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	push_error("StorageAdapter.delete_instance() must be overridden")
	return ERR_UNAVAILABLE

## Rename an instance's file after a name change
func rename_instance_file(item: DataItem, old_name: String, table_name: String, base_path: String) -> Error:
	push_error("StorageAdapter.rename_instance_file() must be overridden")
	return ERR_UNAVAILABLE

## Delete the entire instances directory for a table
func delete_table_instances_dir(table_name: String, base_path: String) -> Error:
	push_error("StorageAdapter.delete_table_instances_dir() must be overridden")
	return ERR_UNAVAILABLE
