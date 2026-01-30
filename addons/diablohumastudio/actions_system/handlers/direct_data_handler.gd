class_name DirectDataHandler
extends ActionHandler

## Handler that directly modifies user data based on action
## Example: When level_completed action fires, set UserLevel.complete = true

var user_data_system: Node  # Reference to UserDataSystem
var data_type: String = ""
var property_to_match: String = "id"  # Property to find the instance (usually "id")
var property_source: String = ""  # Where to get the value from action_data
var properties_to_set: Dictionary = {}  # {property_name: value or "$action_data_key"}


func _init(p_name: String = "DirectDataHandler") -> void:
	super(p_name)


func setup(p_user_data_system: Node, p_data_type: String, p_match_property: String, p_source: String, p_properties: Dictionary) -> void:
	user_data_system = p_user_data_system
	data_type = p_data_type
	property_to_match = p_match_property
	property_source = p_source
	properties_to_set = p_properties


func handle(action_data: Dictionary) -> void:
	if !enabled or !user_data_system:
		return

	# Get the value to match from action data
	var match_value = action_data.get(property_source)
	if match_value == null:
		push_warning("[DirectDataHandler] Missing property in action data: %s" % property_source)
		return

	# Find the instance
	var instance_index = user_data_system.user_data_manager.find_instance_index(
		user_data_system.current_user_id,
		data_type,
		property_to_match,
		match_value
	)

	if instance_index == -1:
		push_warning("[DirectDataHandler] Instance not found: %s.%s = %s" % [data_type, property_to_match, match_value])
		return

	# Get the instance
	var instance = user_data_system.user_data_manager.get_instance(
		user_data_system.current_user_id,
		data_type,
		instance_index
	)

	# Apply property changes
	for prop_name in properties_to_set.keys():
		var value = properties_to_set[prop_name]

		# If value starts with "$", get it from action_data
		if value is String and value.begins_with("$"):
			var key = value.substr(1)
			value = action_data.get(key, value)

		instance[prop_name] = value

	# Update the instance
	user_data_system.user_data_manager.update_instance(
		user_data_system.current_user_id,
		data_type,
		instance_index,
		instance
	)

	print("[DirectDataHandler] Updated %s instance (match: %s = %s)" % [data_type, property_to_match, match_value])


func to_dict() -> Dictionary:
	var base = super.to_dict()
	base["data_type"] = data_type
	base["property_to_match"] = property_to_match
	base["property_source"] = property_source
	base["properties_to_set"] = properties_to_set
	return base


static func from_dict(data: Dictionary, user_data_system: Node= null) -> DirectDataHandler:
	var handler = DirectDataHandler.new(data.get("name", ""))
	handler.enabled = data.get("enabled", true)
	handler.setup(
		user_data_system,
		data.get("data_type", ""),
		data.get("property_to_match", "id"),
		data.get("property_source", ""),
		data.get("properties_to_set", {})
	)
	return handler


func get_handler_type() -> String:
	return "direct_data"
