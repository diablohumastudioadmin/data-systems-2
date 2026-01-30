class_name ActionHandler
extends RefCounted

## Base class for action handlers
## Override handle() method to implement custom behavior

var handler_name: String = ""
var enabled: bool = true


func _init(p_name: String = "ActionHandler") -> void:
	handler_name = p_name


## Handle an action - override in subclasses
func handle(action_data: Dictionary) -> void:
	push_warning("ActionHandler.handle() not implemented in: %s" % handler_name)


## Serialize handler configuration to dictionary
func to_dict() -> Dictionary:
	return {
		"type": get_handler_type(),
		"name": handler_name,
		"enabled": enabled
	}


## Deserialize handler from dictionary
static func from_dict(data: Dictionary, user_data_system: Node = null) -> ActionHandler:
	var handler = ActionHandler.new(data.get("name", ""))
	handler.enabled = data.get("enabled", true)
	return handler


## Get handler type (override in subclasses)
func get_handler_type() -> String:
	return "base"
