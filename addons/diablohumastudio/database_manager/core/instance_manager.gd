@tool
class_name InstanceManager
extends RefCounted

signal data_changed(table_name: String)

var base_path: String
var instances_path: String:
	get: return base_path.path_join("instances/")

var _storage: StorageAdapter
var _schema: SchemaManager

## {table_name: Array[DataItem]} — populated lazily on first access
var _instance_cache: Dictionary = {}
## {table_name: {id_int: DataItem}} — for fast ID lookups
var _id_cache: Dictionary = {}

func _init(p_storage: StorageAdapter, p_schema: SchemaManager, p_base_path: String) -> void:
	_storage = p_storage
	_schema = p_schema
	base_path = p_base_path

# --- Instance Management -----------------------------------------------------

## Get all instances for a table (lazy-loaded from disk on first call)
func get_data_items(table_name: String) -> Array[DataItem]:
	if not _instance_cache.has(table_name):
		_load_table_instances(table_name)
	var items: Array[DataItem] = []
	items.assign(_instance_cache.get(table_name, []))
	return items


## Get a specific instance by its stable ID
func get_by_id(table_name: String, id: int) -> DataItem:
	if not _id_cache.has(table_name):
		_load_table_instances(table_name)
	var cache: Dictionary = _id_cache.get(table_name, {})
	return cache.get(id, null)


## Add a new instance with a required name and a unique ID
func add_instance(table_name: String, instance_name: String) -> DataItem:
	if instance_name.strip_edges().is_empty():
		push_error("Instance name cannot be empty")
		return null

	if not _schema.has_table(table_name):
		push_error("Table not found: %s" % table_name)
		return null

	var item: DataItem = _create_data_item(table_name)
	if item == null:
		return null

	item.name = instance_name.strip_edges()
	item.id = ResourceUID.create_id()

	# Ensure cache is loaded BEFORE saving (so lazy-load doesn't pick up the new file)
	_ensure_table_loaded(table_name)

	# Save to individual .tres file
	_storage.save_instance(item, table_name, base_path)

	# Update caches
	_instance_cache[table_name].append(item)
	_cache_item(table_name, item)

	_request_scan()
	data_changed.emit(table_name)
	return item


## Remove an instance by its stable ID
func remove_instance(table_name: String, id: int) -> bool:
	var item: DataItem = get_by_id(table_name, id)
	if item == null:
		return false

	item._is_deleted = true
	_storage.delete_instance(item, table_name, base_path)

	# Update caches
	if _instance_cache.has(table_name):
		var items: Array = _instance_cache[table_name]
		for i in range(items.size()):
			if items[i].id == id:
				items.remove_at(i)
				break
	_uncache_item(table_name, id)

	_request_scan()
	data_changed.emit(table_name)
	return true


## Save all instances for a table (re-saves each .tres file)
func save_instances(table_name: String) -> Error:
	var items: Array[DataItem] = get_data_items(table_name)
	var last_err := OK
	for item in items:
		var err := _storage.save_instance(item, table_name, base_path)
		if err != OK:
			last_err = err
	
	_request_scan()
	return last_err

## Manually save an instance (used by SchemaManager during rename)
func save_manual_instance(item: DataItem, table_name: String) -> Error:
	var err := _storage.save_instance(item, table_name, base_path)
	_request_scan()
	return err

## Reload instances from disk (invalidates cache)
func load_instances(table_name: String) -> void:
	_instance_cache.erase(table_name)
	_id_cache.erase(table_name)


## Delete all instances for a table
func clear_instances(table_name: String) -> void:
	_storage.delete_table_instances_dir(table_name, base_path)
	# Recreate the empty directory
	var inst_dir := instances_path.path_join(table_name.to_lower())
	DirAccess.make_dir_recursive_absolute(inst_dir)
	_instance_cache[table_name] = []
	_id_cache[table_name] = {}
	_request_scan()
	data_changed.emit(table_name)

## Delete table instances directory (used by SchemaManager.remove_table)
func delete_table_instances_dir(table_name: String) -> void:
	_storage.delete_table_instances_dir(table_name, base_path)

## Clear cache for a table (used by SchemaManager)
func clear_cache(table_name: String) -> void:
	_instance_cache.erase(table_name)
	_id_cache.erase(table_name)

func get_instance_count(table_name: String) -> int:
	return get_data_items(table_name).size()


# --- ID Cache ----------------------------------------------------------------

func _load_table_instances(table_name: String) -> void:
	var items: Array[DataItem] = _storage.load_instances(table_name, base_path)
	_instance_cache[table_name] = items
	_rebuild_table_id_cache(table_name)


func _ensure_table_loaded(table_name: String) -> void:
	if not _instance_cache.has(table_name):
		_load_table_instances(table_name)


func _rebuild_table_id_cache(table_name: String) -> void:
	var items: Array = _instance_cache.get(table_name, [])
	var cache := {}
	for item in items:
		if item.id >= 0:
			cache[item.id] = item
	_id_cache[table_name] = cache


func _cache_item(table_name: String, item: DataItem) -> void:
	if not _id_cache.has(table_name):
		_id_cache[table_name] = {}
	if item.id >= 0:
		_id_cache[table_name][item.id] = item


func _uncache_item(table_name: String, id: int) -> void:
	if _id_cache.has(table_name):
		_id_cache[table_name].erase(id)


# --- Internal ----------------------------------------------------------------

func _create_data_item(table_name: String) -> DataItem:
	var structures_path = base_path.path_join("table_structures/")
	var script_path := structures_path.path_join("%s.gd" % table_name.to_lower())
	if not ResourceLoader.exists(script_path):
		push_error("Resource script not found: %s" % script_path)
		return null

	var script = ResourceLoader.load(
		script_path, "", ResourceLoader.CACHE_MODE_REUSE
	) as GDScript
	if script == null:
		return null

	return script.new()

func _request_scan() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
