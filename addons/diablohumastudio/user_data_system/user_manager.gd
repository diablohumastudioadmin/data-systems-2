class_name UserManager
extends RefCounted

## Manages user accounts and active user selection

signal user_created(user_id: String)
signal user_deleted(user_id: String)
signal active_user_changed(user_id: String)

const USERS_FILE = "user://data_systems/users.json"

var users: Dictionary = {}  # user_id -> {id, name, created_at, last_played}
var active_user_id: String = ""


func _init() -> void:
	load_users()


## Load all users from disk
func load_users() -> Error:
	if !JSONPersistence.file_exists(USERS_FILE):
		_create_default_users_file()
		return OK

	var data = JSONPersistence.load_json(USERS_FILE)
	if data == null:
		push_error("Failed to load users file")
		return ERR_FILE_CORRUPT

	users = data.get("users", {})
	active_user_id = data.get("active_user_id", "")

	print("[UserManager] Loaded %d users" % users.size())
	return OK


## Save all users to disk
func save_users() -> Error:
	var data = {
		"users": users,
		"active_user_id": active_user_id
	}

	return JSONPersistence.save_json(USERS_FILE, data)


## Create a new user
func create_user(user_name: String) -> String:
	# Generate unique ID
	var user_id = _generate_user_id()

	var user_data = {
		"id": user_id,
		"name": user_name,
		"created_at": Time.get_unix_time_from_system(),
		"last_played": Time.get_unix_time_from_system()
	}

	users[user_id] = user_data

	# Set as active user if first user
	if active_user_id.is_empty():
		active_user_id = user_id

	save_users()
	user_created.emit(user_id)

	print("[UserManager] Created user: %s (ID: %s)" % [user_name, user_id])
	return user_id


## Delete a user
func delete_user(user_id: String) -> bool:
	if !users.has(user_id):
		push_warning("User not found: %s" % user_id)
		return false

	users.erase(user_id)

	# Clear active user if it was deleted
	if active_user_id == user_id:
		active_user_id = ""
		# Set to first available user
		if users.size() > 0:
			active_user_id = users.keys()[0]

	save_users()
	user_deleted.emit(user_id)

	print("[UserManager] Deleted user: %s" % user_id)
	return true


## Set active user
func set_active_user(user_id: String) -> bool:
	if !users.has(user_id):
		push_warning("User not found: %s" % user_id)
		return false

	active_user_id = user_id

	# Update last played time
	users[user_id]["last_played"] = Time.get_unix_time_from_system()

	save_users()
	active_user_changed.emit(user_id)

	print("[UserManager] Active user set to: %s" % user_id)
	return true


## Get active user data
func get_active_user() -> Dictionary:
	if active_user_id.is_empty():
		return {}
	return users.get(active_user_id, {})


## Get user by ID
func get_user(user_id: String) -> Dictionary:
	return users.get(user_id, {})


## Get all user IDs
func get_user_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(users.keys())
	return ids


## Check if user exists
func has_user(user_id: String) -> bool:
	return users.has(user_id)


## Get user count
func get_user_count() -> int:
	return users.size()


## Generate unique user ID
func _generate_user_id() -> String:
	return "user_%d" % Time.get_ticks_msec()


## Create default users file
func _create_default_users_file() -> void:
	var data = {
		"users": {},
		"active_user_id": ""
	}
	JSONPersistence.save_json(USERS_FILE, data)
