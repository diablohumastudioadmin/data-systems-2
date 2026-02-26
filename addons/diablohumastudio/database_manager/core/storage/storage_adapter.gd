@tool
class_name StorageAdapter
extends RefCounted

## Abstract base class for storage adapters.
## Implementations handle persistence (save/load/delete) for data instances.

func save_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	push_error("save_instance not implemented")
	return ERR_UNAVAILABLE

func load_instances(table_name: String, base_path: String) -> Array[DataItem]:
	push_error("load_instances not implemented")
	return []

func delete_instance(item: DataItem, table_name: String, base_path: String) -> Error:
	push_error("delete_instance not implemented")
	return ERR_UNAVAILABLE

func rename_instance_file(item: DataItem, old_name: String, table_name: String, base_path: String) -> Error:
	push_error("rename_instance_file not implemented")
	return ERR_UNAVAILABLE

func delete_table_instances_dir(table_name: String, base_path: String) -> Error:
	push_error("delete_table_instances_dir not implemented")
	return ERR_UNAVAILABLE
