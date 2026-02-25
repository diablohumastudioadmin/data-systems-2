@tool
class_name MigrationHelper
extends RefCounted

## One-time migration from v1 (single database.tres) to v2 (per-instance files).
## Reads the old Database resource, saves each instance as an individual .tres,
## regenerates scripts with REQUIRED_FIELDS/FK_FIELDS consts, then deletes
## the old database.tres and ids/ directory.


## Check if v1 database.tres exists (meaning migration is needed)
static func needs_migration(base_path: String) -> bool:
	var db_path := base_path.path_join("database.tres")
	return ResourceLoader.exists(db_path)


## Migrate from v1 to v2 format.
## Returns true on success, false on failure.
static func migrate_v1_to_v2(base_path: String, storage: StorageAdapter) -> bool:
	var db_path := base_path.path_join("database.tres")
	var structures_path := base_path.path_join("table_structures/")

	# Load old database
	var db = ResourceLoader.load(db_path)
	if db == null:
		push_error("[MigrationHelper] Failed to load old database: %s" % db_path)
		return false

	# db is a Database resource with tables: Array[DataTable]
	var tables: Array = db.get("tables")
	if tables == null:
		push_error("[MigrationHelper] No 'tables' property in database")
		return false

	var migrated_count := 0

	for table in tables:
		var table_name: String = table.get("table_name")
		var instances: Array = table.get("instances")
		var field_constraints: Dictionary = table.get("field_constraints")
		var parent_table: String = table.get("parent_table")
		if field_constraints == null:
			field_constraints = {}
		if parent_table == null:
			parent_table = ""

		# 1. Create instances directory and save each item as individual .tres
		if instances != null:
			for item in instances:
				if not item is DataItem:
					continue
				# Assign time-hash ID to replace old sequential IDs
				item.id = ResourceUID.create_id()
				# Null out FK enum int fields (can't auto-migrate int → Resource)
				_null_fk_fields(item, field_constraints)
				# Save as individual file
				storage.save_instance(item, table_name, base_path)
				migrated_count += 1

		# 2. Regenerate .gd script with REQUIRED_FIELDS + FK_FIELDS consts
		#    and Resource FK types instead of enum types
		var fields := _read_own_fields_from_script(table_name, structures_path, parent_table)
		if not fields.is_empty():
			ResourceGenerator.generate_resource_class(
				table_name, fields, structures_path, field_constraints, parent_table)

	# 3. Delete old ids/ directory
	_delete_directory_recursive(base_path.path_join("ids/"))

	# 4. Delete old database.tres
	DirAccess.remove_absolute(db_path)

	# 5. Print summary
	push_warning("[MigrationHelper] Migration complete: %d instances migrated across %d tables. FK fields set to null — reassign manually via Inspector." % [migrated_count, tables.size()])

	return true


## Set FK fields to null (can't auto-migrate int enum → Resource reference)
static func _null_fk_fields(item: DataItem, constraints: Dictionary) -> void:
	for field_name: String in constraints:
		var fc: Dictionary = constraints[field_name]
		if fc.has("foreign_key"):
			item.set(field_name, null)


## Read the own fields from an existing generated script for regeneration.
## Returns Array[Dictionary] with {name, type_string, default}.
static func _read_own_fields_from_script(table_name: String,
		structures_path: String, parent_table: String) -> Array[Dictionary]:
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	if not FileAccess.file_exists(script_path):
		return []

	var source := FileAccess.get_file_as_string(script_path)
	if source.is_empty():
		return []

	# Parse @export lines to extract field info
	var fields: Array[Dictionary] = []
	for line in source.split("\n"):
		line = line.strip_edges()
		if not line.begins_with("@export var "):
			continue
		# Format: @export var name: Type = default
		var after_export := line.substr(12)  # after "@export var "
		var colon_pos := after_export.find(":")
		if colon_pos < 0:
			continue
		var field_name := after_export.substr(0, colon_pos).strip_edges()
		var rest := after_export.substr(colon_pos + 1).strip_edges()
		var eq_pos := rest.find("=")
		var type_str: String
		if eq_pos >= 0:
			type_str = rest.substr(0, eq_pos).strip_edges()
		else:
			type_str = rest.strip_edges()

		# Convert old enum FK types back to base type for regeneration
		# The ResourceGenerator will re-apply FK as Resource type
		if type_str.ends_with("Ids.Id"):
			type_str = "int"

		fields.append({
			"name": field_name,
			"type_string": type_str,
			"default": null  # defaults will be regenerated
		})

	return fields


## Recursively delete a directory and all its contents
static func _delete_directory_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return

	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full := path.path_join(file_name)
		if dir.current_is_dir():
			_delete_directory_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
