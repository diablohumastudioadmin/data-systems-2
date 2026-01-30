class_name NotificationHandler
extends ActionHandler

## Handler that broadcasts signals for game objects to listen to
## Game objects can connect to these signals to react to actions

signal notification_sent(notification_type: String, data: Dictionary)

var notification_type: String = ""


func _init(p_name: String = "NotificationHandler", p_notification_type: String = "") -> void:
	super(p_name)
	notification_type = p_notification_type


func handle(action_data: Dictionary) -> void:
	if !enabled:
		return

	notification_sent.emit(notification_type, action_data)
	print("[NotificationHandler] Sent notification: %s" % notification_type)


func to_dict() -> Dictionary:
	var base = super.to_dict()
	base["notification_type"] = notification_type
	return base


static func from_dict(data: Dictionary, user_data_system: Node = null) -> NotificationHandler:
	var handler = NotificationHandler.new(
		data.get("name", ""),
		data.get("notification_type", "")
	)
	handler.enabled = data.get("enabled", true)
	return handler


func get_handler_type() -> String:
	return "notification"
