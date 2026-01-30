class_name ActionRegistry
extends RefCounted

## Manages action configurations and handlers
## Loads/saves action configurations from JSON

const ACTIONS_FILE = "res://data/actions.json"

var actions: Dictionary = {}  # action_type -> {handlers: Array[Dictionary]}
var user_data_system: Node  # Reference for creating handlers


func _init(p_user_data_system: Node = null) -> void:
	user_data_system = p_user_data_system
	load_actions()


## Load action configurations from disk
func load_actions() -> Error:
	if !JSONPersistence.file_exists(ACTIONS_FILE):
		_create_default_actions_file()
		return OK

	var data = JSONPersistence.load_json(ACTIONS_FILE)
	if data == null:
		push_error("Failed to load actions file")
		return ERR_FILE_CORRUPT

	actions = data.get("actions", {})
	print("[ActionRegistry] Loaded %d action types" % actions.size())
	return OK


## Save action configurations to disk
func save_actions() -> Error:
	var data = {
		"version": 1,
		"actions": actions
	}

	var error = JSONPersistence.save_json(ACTIONS_FILE, data)
	if error == OK:
		print("[ActionRegistry] Saved actions configuration")
	return error


## Add a handler configuration to an action
func add_handler_config(action_type: String, handler_config: Dictionary) -> void:
	if !actions.has(action_type):
		actions[action_type] = {"handlers": []}

	actions[action_type]["handlers"].append(handler_config)
	save_actions()


## Remove a handler configuration
func remove_handler_config(action_type: String, handler_index: int) -> bool:
	if !actions.has(action_type):
		return false

	var handlers = actions[action_type]["handlers"]
	if handler_index < 0 or handler_index >= handlers.size():
		return false

	handlers.remove_at(handler_index)
	save_actions()
	return true


## Get all handler configurations for an action
func get_handler_configs(action_type: String) -> Array:
	if actions.has(action_type):
		return actions[action_type].get("handlers", [])
	return []


## Create handler instances from configurations
func create_handlers(action_type: String) -> Array[ActionHandler]:
	var handler_instances: Array[ActionHandler] = []
	var configs = get_handler_configs(action_type)

	for config in configs:
		var handler = _create_handler_from_config(config)
		if handler:
			handler_instances.append(handler)

	return handler_instances


## Create a handler instance from configuration dictionary
func _create_handler_from_config(config: Dictionary) -> ActionHandler:
	var handler_type = config.get("type", "base")

	match handler_type:
		"direct_data":
			return DirectDataHandler.from_dict(config, user_data_system)
		"notification":
			return NotificationHandler.from_dict(config)
		_:
			return ActionHandler.from_dict(config)


## Get all action types
func get_action_types() -> Array[String]:
	var types: Array[String] = []
	types.assign(actions.keys())
	return types


## Add a new action type
func add_action_type(action_type: String) -> void:
	if !actions.has(action_type):
		actions[action_type] = {"handlers": []}
		save_actions()


## Remove an action type
func remove_action_type(action_type: String) -> bool:
	if actions.has(action_type):
		actions.erase(action_type)
		save_actions()
		return true
	return false


## Create default actions file
func _create_default_actions_file() -> void:
	var data = {
		"version": 1,
		"actions": {}
	}
	JSONPersistence.save_json(ACTIONS_FILE, data)
