@tool
class_name StorageAdapter
extends RefCounted

## Abstract interface for database persistence.
## Override load_database() and save_database() in subclasses.

## Load the entire database from storage
func load_database(path: String) -> Database:
	push_error("StorageAdapter.load_database() must be overridden")
	return null

## Save the entire database to storage
func save_database(database: Database, path: String) -> Error:
	push_error("StorageAdapter.save_database() must be overridden")
	return ERR_UNAVAILABLE
