class_name ActionDispatcher
extends RefCounted

## Dispatches actions to registered handlers and emits signals

signal action_dispatched(action_type: String, action_data: Dictionary)

var action_registry: ActionRegistry
var handlers: Dictionary = {}  # action_type -> Array[ActionHandler]
var signal_listeners: Dictionary = {}  # action_type -> Signal


func _init(p_registry: ActionRegistry) -> void:
	action_registry = p_registry


## Dispatch an action
func dispatch(action_type: String, action_data: Dictionary = {}) -> void:
	print("[ActionDispatcher] Dispatching: %s" % action_type)

	# Execute registered handlers
	if handlers.has(action_type):
		for handler in handlers[action_type]:
			handler.handle(action_data)

	# Emit signal for notification handlers
	action_dispatched.emit(action_type, action_data)

	# Emit specific action signal if exists
	if signal_listeners.has(action_type):
		_emit_action_signal(action_type, action_data)


## Register a handler for an action type
func register_handler(action_type: String, handler: ActionHandler) -> void:
	if !handlers.has(action_type):
		handlers[action_type] = []

	if handler not in handlers[action_type]:
		handlers[action_type].append(handler)
		print("[ActionDispatcher] Registered handler for: %s" % action_type)


## Unregister a handler
func unregister_handler(action_type: String, handler: ActionHandler) -> void:
	if handlers.has(action_type):
		handlers[action_type].erase(handler)


## Register a signal for an action type (for game objects to connect to)
func register_signal(action_type: String) -> void:
	if !signal_listeners.has(action_type):
		signal_listeners[action_type] = Signal()
		print("[ActionDispatcher] Registered signal for: %s" % action_type)


## Get signal for an action type
func get_action_signal(action_type: String) -> Signal:
	if !signal_listeners.has(action_type):
		register_signal(action_type)
	return action_dispatched


## Emit action-specific signal
func _emit_action_signal(action_type: String, action_data: Dictionary) -> void:
	# For now, just use the main signal
	# In future, could create dynamic signals per action type
	pass


## Clear all handlers
func clear_handlers() -> void:
	handlers.clear()
	signal_listeners.clear()
