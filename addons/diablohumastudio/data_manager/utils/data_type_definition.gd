class_name DataTypeDefinition
extends RefCounted

## Defines the schema for a data type
## Stores property definitions (name, type, default value)

# Supported property types
enum PropertyType {
	INT,
	FLOAT,
	STRING,
	BOOL,
	TEXTURE2D,
	VECTOR2,
	VECTOR3,
	COLOR,
	ARRAY,
	DICTIONARY
}

# Type name to enum mapping
const TYPE_NAME_MAP = {
	"int": PropertyType.INT,
	"float": PropertyType.FLOAT,
	"String": PropertyType.STRING,
	"bool": PropertyType.BOOL,
	"Texture2D": PropertyType.TEXTURE2D,
	"Vector2": PropertyType.VECTOR2,
	"Vector3": PropertyType.VECTOR3,
	"Color": PropertyType.COLOR,
	"Array": PropertyType.ARRAY,
	"Dictionary": PropertyType.DICTIONARY
}

# Enum to type name mapping
const TYPE_ENUM_MAP = {
	PropertyType.INT: "int",
	PropertyType.FLOAT: "float",
	PropertyType.STRING: "String",
	PropertyType.BOOL: "bool",
	PropertyType.TEXTURE2D: "Texture2D",
	PropertyType.VECTOR2: "Vector2",
	PropertyType.VECTOR3: "Vector3",
	PropertyType.COLOR: "Color",
	PropertyType.ARRAY: "Array",
	PropertyType.DICTIONARY: "Dictionary"
}

# Default values for each type
const TYPE_DEFAULTS = {
	PropertyType.INT: 0,
	PropertyType.FLOAT: 0.0,
	PropertyType.STRING: "",
	PropertyType.BOOL: false,
	PropertyType.TEXTURE2D: null,
	PropertyType.VECTOR2: Vector2.ZERO,
	PropertyType.VECTOR3: Vector3.ZERO,
	PropertyType.COLOR: Color.WHITE,
	PropertyType.ARRAY: [],
	PropertyType.DICTIONARY: {}
}

## Data type metadata
var type_name: String = ""  # e.g., "Level", "Achievement"
var is_user_data: bool = false  # true for user data types, false for master data
var properties: Array[Dictionary] = []  # Array of {name: String, type: PropertyType, default: Variant}


func _init(p_type_name: String = "", p_is_user_data: bool = false) -> void:
	type_name = p_type_name
	is_user_data = p_is_user_data


## Add a property to the definition
func add_property(property_name: String, property_type: PropertyType, default_value: Variant = null) -> void:
	# Use type default if no default provided
	if default_value == null:
		default_value = TYPE_DEFAULTS.get(property_type, null)

	properties.append({
		"name": property_name,
		"type": property_type,
		"default": default_value
	})


## Remove a property by name
func remove_property(property_name: String) -> bool:
	for i in range(properties.size()):
		if properties[i].name == property_name:
			properties.remove_at(i)
			return true
	return false


## Get property definition by name
func get_property(property_name: String) -> Dictionary:
	for prop in properties:
		if prop.name == property_name:
			return prop
	return {}


## Check if property exists
func has_property(property_name: String) -> bool:
	return !get_property(property_name).is_empty()


## Serialize to dictionary (for JSON)
func to_dict() -> Dictionary:
	var props_array: Array = []
	for prop in properties:
		props_array.append({
			"name": prop.name,
			"type": TYPE_ENUM_MAP[prop.type],
			"default": _serialize_default_value(prop.default, prop.type)
		})

	return {
		"type_name": type_name,
		"is_user_data": is_user_data,
		"properties": props_array
	}


## Deserialize from dictionary (from JSON)
static func from_dict(data: Dictionary) -> DataTypeDefinition:
	var definition = DataTypeDefinition.new(
		data.get("type_name", ""),
		data.get("is_user_data", false)
	)

	var props = data.get("properties", [])
	for prop_data in props:
		var type_name_str = prop_data.get("type", "String")
		var prop_type = TYPE_NAME_MAP.get(type_name_str, PropertyType.STRING)
		var default_val = _deserialize_default_value(prop_data.get("default"), prop_type)

		definition.add_property(
			prop_data.get("name", ""),
			prop_type,
			default_val
		)

	return definition


## Serialize default value for JSON storage
func _serialize_default_value(value: Variant, prop_type: PropertyType) -> Variant:
	match prop_type:
		PropertyType.TEXTURE2D:
			# Store texture path as string
			if value is Texture2D:
				return value.resource_path
			return null
		PropertyType.VECTOR2:
			if value is Vector2:
				return {"x": value.x, "y": value.y}
			return {"x": 0, "y": 0}
		PropertyType.VECTOR3:
			if value is Vector3:
				return {"x": value.x, "y": value.y, "z": value.z}
			return {"x": 0, "y": 0, "z": 0}
		PropertyType.COLOR:
			if value is Color:
				return value.to_html()
			return "#FFFFFF"
		_:
			return value


## Deserialize default value from JSON
static func _deserialize_default_value(value: Variant, prop_type: PropertyType) -> Variant:
	match prop_type:
		PropertyType.TEXTURE2D:
			# Load texture from path
			if value is String and !value.is_empty():
				return load(value)
			return null
		PropertyType.VECTOR2:
			if value is Dictionary:
				return Vector2(value.get("x", 0), value.get("y", 0))
			return Vector2.ZERO
		PropertyType.VECTOR3:
			if value is Dictionary:
				return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
			return Vector3.ZERO
		PropertyType.COLOR:
			if value is String:
				return Color.html(value)
			return Color.WHITE
		_:
			return value


## Validate a data instance against this definition
func validate_instance(instance_data: Dictionary) -> bool:
	# Check that all required properties exist
	for prop in properties:
		if !instance_data.has(prop.name):
			push_warning("Instance missing property: %s" % prop.name)
			return false
	return true


## Create a default instance from this definition
func create_default_instance() -> Dictionary:
	var instance = {}
	for prop in properties:
		instance[prop.name] = prop.default
	return instance
