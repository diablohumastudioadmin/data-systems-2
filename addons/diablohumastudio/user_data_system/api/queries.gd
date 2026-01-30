class_name UserDataQueries
extends RefCounted

## Fluent query interface for user data
## Example: UserDataSystem.queries.get_user_level_by_id(5).set_complete(true)

var user_data_system: Node  # Reference to UserDataSystem singleton


func _init(p_system: Node) -> void:
	user_data_system = p_system


## Generic query builder
func get_by_id(type_name: String, id: Variant) -> UserDataQuery:
	return UserDataQuery.new(user_data_system, type_name, "id", id)


## Specific query methods (examples - can be extended)
func get_user_level_by_id(level_id: Variant) -> UserDataQuery:
	return get_by_id("UserLevel", level_id)


func get_achievement_by_id(achievement_id: Variant) -> UserDataQuery:
	return get_by_id("AchievementProgress", achievement_id)


## Query result class with fluent methods
class UserDataQuery:
	var system: Node
	var type_name: String
	var property_name: String
	var property_value: Variant
	var _cached_data: Dictionary = {}
	var _is_loaded: bool = false

	func _init(p_system: Node, p_type: String, p_prop: String, p_value: Variant) -> void:
		system = p_system
		type_name = p_type
		property_name = p_prop
		property_value = p_value

	## Load the data
	func _ensure_loaded() -> void:
		if !_is_loaded:
			_cached_data = system.get_data(type_name, property_name, property_value)
			_is_loaded = true

	## Get the full data dictionary
	func get_data() -> Dictionary:
		_ensure_loaded()
		return _cached_data

	## Check if data exists
	func exists() -> bool:
		_ensure_loaded()
		return !_cached_data.is_empty()

	## Get a specific property
	func get_property(prop_name: String) -> Variant:
		_ensure_loaded()
		return _cached_data.get(prop_name)

	## Set a specific property
	func set_property(prop_name: String, value: Variant) -> bool:
		_ensure_loaded()
		if _cached_data.is_empty():
			return false

		_cached_data[prop_name] = value
		return system.update_data(type_name, property_name, property_value, _cached_data)

	## Convenience methods for common properties
	func set_complete(value: bool) -> bool:
		return set_property("complete", value)

	func set_unlocked(value: bool) -> bool:
		return set_property("unlocked", value)

	func set_achieved(value: bool) -> bool:
		return set_property("achieved", value)

	func is_complete() -> bool:
		return get_property("complete")

	func is_unlocked() -> bool:
		return get_property("unlocked")

	func is_achieved() -> bool:
		return get_property("achieved")

	## Update multiple properties at once
	func update(updates: Dictionary) -> bool:
		_ensure_loaded()
		if _cached_data.is_empty():
			return false

		for key in updates.keys():
			_cached_data[key] = updates[key]

		return system.update_data(type_name, property_name, property_value, _cached_data)
