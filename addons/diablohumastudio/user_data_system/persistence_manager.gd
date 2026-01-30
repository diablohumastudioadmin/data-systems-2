class_name PersistenceManager
extends RefCounted

## Handles saving and loading user data to/from disk

var user_data_manager: UserDataManager


func _init(p_user_data_manager: UserDataManager) -> void:
	user_data_manager = p_user_data_manager


## Save user data to disk
func save_user_data(user_id: String) -> Error:
	var file_path = _get_user_data_file(user_id)
	var data = user_data_manager.get_user_data(user_id)

	var save_data = {
		"version": 1,
		"user_id": user_id,
		"saved_at": Time.get_unix_time_from_system(),
		"data": data
	}

	var error = JSONPersistence.save_json(file_path, save_data)
	if error == OK:
		print("[PersistenceManager] Saved data for user: %s" % user_id)
	else:
		push_error("Failed to save user data: %s" % user_id)

	return error


## Load user data from disk
func load_user_data(user_id: String) -> Error:
	var file_path = _get_user_data_file(user_id)

	if !JSONPersistence.file_exists(file_path):
		print("[PersistenceManager] No save file found for user: %s" % user_id)
		user_data_manager.initialize_user_data(user_id)
		return OK

	var save_data = JSONPersistence.load_json(file_path)
	if save_data == null:
		push_error("Failed to load user data: %s" % user_id)
		return ERR_FILE_CORRUPT

	# Verify user ID matches
	if save_data.get("user_id") != user_id:
		push_warning("User ID mismatch in save file")

	var data = save_data.get("data", {})
	user_data_manager.set_user_data(user_id, data)

	print("[PersistenceManager] Loaded data for user: %s" % user_id)
	return OK


## Delete user data file
func delete_user_data(user_id: String) -> Error:
	var file_path = _get_user_data_file(user_id)
	return JSONPersistence.delete_file(file_path)


## Check if user data file exists
func has_user_data(user_id: String) -> bool:
	var file_path = _get_user_data_file(user_id)
	return JSONPersistence.file_exists(file_path)


## Create backup of user data
func backup_user_data(user_id: String) -> Error:
	var file_path = _get_user_data_file(user_id)
	return JSONPersistence.create_backup(file_path)


## Restore user data from backup
func restore_user_data_backup(user_id: String) -> Error:
	var file_path = _get_user_data_file(user_id)
	return JSONPersistence.restore_backup(file_path)


## Get user data file path
func _get_user_data_file(user_id: String) -> String:
	return JSONPersistence.get_user_data_path("saves/%s/data.json" % user_id)


## Auto-save functionality
var auto_save_enabled: bool = true
var auto_save_interval: float = 300.0  # 5 minutes
var auto_save_timer: float = 0.0
var current_user_id: String = ""


func set_auto_save(enabled: bool, interval: float = 300.0) -> void:
	auto_save_enabled = enabled
	auto_save_interval = interval
	auto_save_timer = 0.0


func process_auto_save(delta: float, user_id: String) -> void:
	if !auto_save_enabled or user_id.is_empty():
		return

	current_user_id = user_id
	auto_save_timer += delta

	if auto_save_timer >= auto_save_interval:
		save_user_data(user_id)
		auto_save_timer = 0.0
