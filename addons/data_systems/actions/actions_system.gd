extends Node

## Actions System - Main singleton for action/event management
## Auto-loaded as ActionsSystem

signal action_fired(action_type: String, action_data: Dictionary)

var action_registry: ActionRegistry
var action_dispatcher: ActionDispatcher


func _ready() -> void:
	# Wait for UserDataSystem to be ready
	await get_tree().process_frame

	# Initialize subsystems
	if has_node("/root/UserDataSystem"):
		var user_data_system = get_node("/root/UserDataSystem")
		action_registry = ActionRegistry.new(user_data_system)
		action_dispatcher = ActionDispatcher.new(action_registry)

		# Register handlers from config
		_register_configured_handlers()

		# Connect signals
		action_dispatcher.action_dispatched.connect(_on_action_dispatched)

		print("[ActionsSystem] Initialized")
	else:
		push_error("[ActionsSystem] UserDataSystem not found!")


## Dispatch an action
func dispatch(action_type: String, action_data: Dictionary = {}) -> void:
	if !action_dispatcher:
		push_error("[ActionsSystem] Not initialized!")
		return

	action_dispatcher.dispatch(action_type, action_data)
	action_fired.emit(action_type, action_data)


## Register a scriptable handler
func register_handler(action_type: String, handler: ActionHandler) -> void:
	if action_dispatcher:
		action_dispatcher.register_handler(action_type, handler)


## Unregister a handler
func unregister_handler(action_type: String, handler: ActionHandler) -> void:
	if action_dispatcher:
		action_dispatcher.unregister_handler(action_type, handler)


## Get signal for an action type (for game objects to connect to)
func on_action(action_type: String) -> Signal:
	if action_dispatcher:
		return action_dispatcher.action_dispatched
	return action_fired


## Register handlers from configuration file
func _register_configured_handlers() -> void:
	for action_type in action_registry.get_action_types():
		var handlers = action_registry.create_handlers(action_type)
		for handler in handlers:
			action_dispatcher.register_handler(action_type, handler)

	print("[ActionsSystem] Registered %d action types" % action_registry.get_action_types().size())


## Reload handlers from configuration
func reload_handlers() -> void:
	if action_dispatcher:
		action_dispatcher.clear_handlers()
	if action_registry:
		action_registry.load_actions()
		_register_configured_handlers()


func _on_action_dispatched(action_type: String, action_data: Dictionary) -> void:
	# Can add logging or debugging here
	pass


## Helper function to create a direct data handler configuration
static func create_direct_data_handler_config(
	handler_name: String,
	data_type: String,
	match_property: String,
	source_property: String,
	properties_to_set: Dictionary
) -> Dictionary:
	return {
		"type": "direct_data",
		"name": handler_name,
		"enabled": true,
		"data_type": data_type,
		"property_to_match": match_property,
		"property_source": source_property,
		"properties_to_set": properties_to_set
	}


## Helper function to create a notification handler configuration
static func create_notification_handler_config(
	handler_name: String,
	notification_type: String
) -> Dictionary:
	return {
		"type": "notification",
		"name": handler_name,
		"enabled": true,
		"notification_type": notification_type
	}
