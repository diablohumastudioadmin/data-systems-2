extends Node

## User Data System - Main singleton for user data management
## Auto-loaded as UserDataSystem

const UserDataQueries = preload("res://addons/data_systems/user_data/api/queries.gd")

signal user_data_loaded(user_id: String)
signal user_data_saved(user_id: String)

var type_registry: DataTypeRegistry
var user_manager: UserManager
var user_data_manager: UserDataManager
var persistence_manager: PersistenceManager
var queries: UserDataQueries  # Fluent query API

# Quick access properties
var current_user_id: String = "":
	get: return user_manager.active_user_id if user_manager else ""


func _ready() -> void:
	# Initialize subsystems
	type_registry = DataTypeRegistry.new()
	user_manager = UserManager.new()
	user_data_manager = UserDataManager.new(type_registry)
	persistence_manager = PersistenceManager.new(user_data_manager)
	queries = UserDataQueries.new(self)

	# Connect signals
	user_manager.active_user_changed.connect(_on_active_user_changed)

	# Load active user data if exists
	if !user_manager.active_user_id.is_empty():
		load_user_data(user_manager.active_user_id)

	print("[UserDataSystem] Initialized")


func _process(delta: float) -> void:
	# Handle auto-save
	if persistence_manager and !current_user_id.is_empty():
		persistence_manager.process_auto_save(delta, current_user_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Auto-save on quit
		if !current_user_id.is_empty():
			save_user_data(current_user_id)


## Create a new user
func create_user(user_name: String) -> String:
	var user_id = user_manager.create_user(user_name)
	user_data_manager.initialize_user_data(user_id)
	persistence_manager.save_user_data(user_id)
	return user_id


## Delete a user
func delete_user(user_id: String) -> bool:
	persistence_manager.delete_user_data(user_id)
	return user_manager.delete_user(user_id)


## Set active user
func set_active_user(user_id: String) -> bool:
	if user_manager.set_active_user(user_id):
		load_user_data(user_id)
		return true
	return false


## Load user data from disk
func load_user_data(user_id: String) -> Error:
	var error = persistence_manager.load_user_data(user_id)
	if error == OK:
		user_data_loaded.emit(user_id)
	return error


## Save user data to disk
func save_user_data(user_id: String = "") -> Error:
	if user_id.is_empty():
		user_id = current_user_id

	if user_id.is_empty():
		push_warning("No user to save")
		return ERR_UNAVAILABLE

	var error = persistence_manager.save_user_data(user_id)
	if error == OK:
		user_data_saved.emit(user_id)
	return error


## Get user data instance by type and property
func get_data(type_name: String, property_name: String, value: Variant) -> Dictionary:
	return user_data_manager.get_instance_by(current_user_id, type_name, property_name, value)


## Get all instances of a type for current user
func get_all_data(type_name: String) -> Array:
	return user_data_manager.get_instances(current_user_id, type_name)


## Add data instance for current user
func add_data(type_name: String, instance_data: Dictionary) -> bool:
	return user_data_manager.add_instance(current_user_id, type_name, instance_data)


## Update data instance for current user
func update_data(type_name: String, property_name: String, property_value: Variant, new_data: Dictionary) -> bool:
	return user_data_manager.update_instance_property(current_user_id, type_name, property_name, property_value, new_data)


## Set a specific property on data instance
func set_data_property(type_name: String, property_name: String, property_value: Variant, target_property: String, new_value: Variant) -> bool:
	var index = user_data_manager.find_instance_index(current_user_id, type_name, property_name, property_value)
	if index == -1:
		return false
	return user_data_manager.set_instance_property(current_user_id, type_name, index, target_property, new_value)


func _on_active_user_changed(user_id: String) -> void:
	load_user_data(user_id)
