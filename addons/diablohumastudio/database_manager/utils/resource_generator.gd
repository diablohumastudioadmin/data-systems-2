@tool
class_name ResourceGenerator
extends RefCounted

## Generates GDScript Resource classes (table structures).
## Creates .gd files that serve as both schema definitions and typed DataItem subclasses.
## FK fields generate Resource references (e.g. @export var weapon: Weapon = null).
## Constraints are embedded as REQUIRED_FIELDS and FK_FIELDS consts.

const DEFAULT_STRUCTURES_PATH = "res://database/res/table_structures/"

## Primitive and built-in types always recognised as valid type strings
const PRIMITIVE_TYPES: Array[String] = [
	"int", "float", "String", "bool",
	"Vector2", "Vector2i", "Vector3", "Vector3i",
	"Color", "Rect2", "Rect2i",
	"Transform2D", "Transform3D", "Basis", "Quaternion", "Plane", "AABB",
	"Array", "Dictionary", "Variant",
	"Resource", "Node", "Object",
	"Texture2D", "Texture", "Image",
	"StringName", "NodePath", "RID",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array",
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
	"PackedVector2Array", "PackedVector3Array", "PackedColorArray",
]

## Editor widget type — determines which default-value control to show
enum DefaultEditorType { INT, FLOAT, STRING, BOOL, COLOR, VECTOR2, VECTOR3, TEXTURE2D, NONE }


# --- Resource Class Generation -----------------------------------------------

## Generate Resource class file from table name and fields.
## fields: Array of {name: String, type_string: String, default: Variant}
## constraints: {field_name: {required: bool, foreign_key: String}}
static func generate_resource_class(table_name: String, fields: Array[Dictionary],
		base_path: String = DEFAULT_STRUCTURES_PATH, constraints: Dictionary = {},
		parent_class: String = "") -> Error:
	var file_path = base_path.path_join(table_name.to_lower() + ".gd")
	var parent_script_path: String = ""
	if not parent_class.is_empty():
		parent_script_path = base_path.path_join(parent_class.to_lower() + ".gd")
	var script_content = _generate_script_content(table_name, fields, constraints, parent_class, parent_script_path)

	var error = _ensure_directory(base_path)
	if error != OK:
		push_error("Failed to create resources directory")
		return error

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		push_error("Failed to create resource file: %s (Error: %d)" % [file_path, error])
		return error

	file.store_string(script_content)
	file.close()

	return OK


## Delete resource class file
static func delete_resource_class(table_name: String, base_path: String = DEFAULT_STRUCTURES_PATH) -> Error:
	var file_path = base_path.path_join(table_name.to_lower() + ".gd")
	if !FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND
	var dir = DirAccess.open(base_path)
	if dir == null:
		return DirAccess.get_open_error()
	var err := dir.remove(file_path.get_file())
	# Also remove .gd.uid file if it exists
	var uid_path: String = file_path + ".uid"
	if FileAccess.file_exists(uid_path):
		dir.remove(uid_path.get_file())
	return err


## Check if resource class exists
static func resource_exists(table_name: String, base_path: String = DEFAULT_STRUCTURES_PATH) -> bool:
	return FileAccess.file_exists(base_path.path_join(table_name.to_lower() + ".gd"))


## Regenerate all resource classes
static func regenerate_all(table_data: Array[Dictionary], base_path: String = DEFAULT_STRUCTURES_PATH) -> int:
	var count = 0
	for entry in table_data:
		if generate_resource_class(entry.table_name, entry.fields, base_path) == OK:
			count += 1
	return count


# --- Type String Utilities ---------------------------------------------------

## Converts a reflection property info dict → raw GDScript type string.
## Used when loading an existing table's schema back into the editor.
static func property_info_to_type_string(prop: Dictionary) -> String:
	match prop.type:
		TYPE_INT:        return "int"
		TYPE_FLOAT:      return "float"
		TYPE_STRING:     return "String"
		TYPE_BOOL:       return "bool"
		TYPE_VECTOR2:    return "Vector2"
		TYPE_VECTOR3:    return "Vector3"
		TYPE_COLOR:      return "Color"
		TYPE_OBJECT:
			var cls: String = prop.get("class_name", "")
			return cls if not cls.is_empty() else "Resource"
		TYPE_ARRAY:
			var hs: String = prop.get("hint_string", "")
			if hs.is_empty():
				return "Array"
			return "Array[%s]" % _hint_part_to_type(hs)
		TYPE_DICTIONARY:
			var hs: String = prop.get("hint_string", "")
			if hs.is_empty() or not ";" in hs:
				return "Dictionary"
			var parts = hs.split(";")
			return "Dictionary[%s, %s]" % [_hint_part_to_type(parts[0]), _hint_part_to_type(parts[1])]
		_:
			return "Variant"


## Parse a Godot hint_string part like "4:String" or "2:int" → type name string.
static func _hint_part_to_type(part: String) -> String:
	var colon := part.find(":")
	if colon < 0:
		return part
	var name_str := part.substr(colon + 1)
	if not name_str.is_empty():
		return name_str
	var num_str := part.substr(0, colon)
	if num_str.is_valid_int():
		match int(num_str):
			TYPE_INT:    return "int"
			TYPE_FLOAT:  return "float"
			TYPE_STRING: return "String"
			TYPE_BOOL:   return "bool"
			TYPE_VECTOR2: return "Vector2"
			TYPE_VECTOR3: return "Vector3"
			TYPE_COLOR:  return "Color"
	return "Variant"


## Returns an error message if ts is invalid, or empty string if valid.
## Validates primitives, typed Array/Dictionary (recursively), engine classes,
## enums (Foo.Bar), and user GDScript class_names.
static func validate_type_string(ts: String) -> String:
	ts = ts.strip_edges()
	if ts.is_empty():
		return "Type cannot be empty"

	if ts in PRIMITIVE_TYPES:
		return ""

	if ts.begins_with("Array[") and ts.ends_with("]"):
		var inner := ts.substr(6, ts.length() - 7)
		var err := validate_type_string(inner)
		if not err.is_empty():
			return "Invalid element type in Array: %s" % err
		return ""

	if ts.begins_with("Dictionary[") and ts.ends_with("]"):
		var inner := ts.substr(11, ts.length() - 12)
		var comma := find_top_level_comma(inner)
		if comma < 0:
			return "Dictionary requires two types: Dictionary[Key, Value]"
		var k := inner.substr(0, comma).strip_edges()
		var v := inner.substr(comma + 1).strip_edges()
		var k_err := validate_type_string(k)
		if not k_err.is_empty():
			return "Invalid key type in Dictionary: %s" % k_err
		var v_err := validate_type_string(v)
		if not v_err.is_empty():
			return "Invalid value type in Dictionary: %s" % v_err
		return ""

	if "." in ts:
		var dot := ts.find(".")
		var class_part := ts.substr(0, dot)
		var enum_part := ts.substr(dot + 1)
		if enum_part.is_empty():
			return "Expected enum name after '%s.'" % class_part
		if ClassDB.class_exists(class_part):
			if ClassDB.class_has_enum(class_part, enum_part):
				return ""
			return "Unknown enum '%s' in '%s'" % [enum_part, class_part]
		if _is_user_class(class_part):
			if _user_class_has_enum(class_part, enum_part):
				return ""
			return "Unknown enum '%s' in '%s'" % [enum_part, class_part]
		return "Unknown class '%s'" % class_part

	if ClassDB.class_exists(ts):
		return ""

	if _is_user_class(ts):
		return ""

	return "'%s' is not a valid GDScript type" % ts


## Returns true if ts is a syntactically valid GDScript type expression.
static func is_valid_type_string(ts: String) -> bool:
	ts = ts.strip_edges()
	if ts.is_empty():
		return false

	# Primitive / built-in
	if ts in PRIMITIVE_TYPES:
		return true

	# Typed Array: "Array[X]"
	if ts.begins_with("Array[") and ts.ends_with("]"):
		var inner := ts.substr(6, ts.length() - 7)
		return is_valid_type_string(inner)

	# Typed Dictionary: "Dictionary[K, V]"
	if ts.begins_with("Dictionary[") and ts.ends_with("]"):
		var inner := ts.substr(11, ts.length() - 12)
		var comma := find_top_level_comma(inner)
		if comma < 0:
			return false
		var k := inner.substr(0, comma).strip_edges()
		var v := inner.substr(comma + 1).strip_edges()
		return is_valid_type_string(k) and is_valid_type_string(v)

	# Enum: "Foo.Bar" — check both the class and the enum name
	if "." in ts:
		var dot := ts.find(".")
		var class_part := ts.substr(0, dot)
		var enum_part := ts.substr(dot + 1)
		if enum_part.is_empty():
			return false
		if ClassDB.class_exists(class_part):
			return ClassDB.class_has_enum(class_part, enum_part)
		return _user_class_has_enum(class_part, enum_part)

	# Engine class
	if ClassDB.class_exists(ts):
		return true

	# User-defined GDScript class_name
	return _is_user_class(ts)


## Find the index of the first comma not inside brackets.
static func find_top_level_comma(s: String) -> int:
	var depth := 0
	for i in range(s.length()):
		var c := s[i]
		if c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
		elif c == "," and depth == 0:
			return i
	return -1


## Check if a user-defined class has a specific enum.
## Loads the script and checks its constant map (enums are stored as Dictionary constants).
static func _user_class_has_enum(cls: String, enum_name: String) -> bool:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == cls:
			var script = load(entry.get("path", ""))
			if script:
				return enum_name in script.get_script_constant_map()
	return false


## Check if name is a user-defined GDScript class (has class_name declaration).
## Uses ProjectSettings.get_global_class_list() which Godot keeps up to date.
static func _is_user_class(name: String) -> bool:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == name:
			return true
	return false


## Returns the DefaultEditorType for a type string —
## determines which default-value widget to show in the field editor row.
static func get_editor_type(ts: String) -> DefaultEditorType:
	match ts.strip_edges():
		"int":       return DefaultEditorType.INT
		"float":     return DefaultEditorType.FLOAT
		"String":    return DefaultEditorType.STRING
		"bool":      return DefaultEditorType.BOOL
		"Color":     return DefaultEditorType.COLOR
		"Vector2":   return DefaultEditorType.VECTOR2
		"Vector3":   return DefaultEditorType.VECTOR3
		"Texture2D": return DefaultEditorType.TEXTURE2D
	return DefaultEditorType.NONE


# --- Script Content Generation -----------------------------------------------

static func _generate_script_content(table_name: String, fields: Array[Dictionary],
		constraints: Dictionary = {}, _parent_class: String = "",
		parent_script_path: String = "") -> String:
	var lines: Array[String] = []

	lines.append("@tool")
	lines.append("class_name %s" % table_name)
	if not parent_script_path.is_empty():
		lines.append('extends "%s"' % parent_script_path)
	else:
		lines.append("extends DataItem")
	lines.append("")
	lines.append("## Auto-generated DataItem subclass for %s table" % table_name)
	lines.append("## Generated by Data Systems Plugin — do not edit manually")
	lines.append("")

	# Collect constraint data for _init() override
	var required_fields: Array[String] = []
	var fk_entries: Array[String] = []
	for field in fields:
		var fc: Dictionary = constraints.get(field.name, {})
		if fc.get("required", false):
			required_fields.append('"%s"' % field.name)
		if fc.has("foreign_key"):
			fk_entries.append('"%s": "%s"' % [field.name, fc["foreign_key"]])

	# Generate _init() that sets constraint vars declared in DataItem base class.
	# GDScript disallows redeclaring vars/consts in child classes, so we override
	# values in _init() instead.
	var has_constraints := not required_fields.is_empty() or not fk_entries.is_empty()
	if has_constraints:
		lines.append("func _init():")
		if not required_fields.is_empty():
			lines.append("\t_required_fields = [%s]" % ", ".join(required_fields))
		if not fk_entries.is_empty():
			lines.append("\t_fk_fields = {%s}" % ", ".join(fk_entries))
		lines.append("")

	for field in fields:
		var type_str: String = field.get("type_string", "Variant")
		var fc: Dictionary = constraints.get(field.name, {})
		if fc.has("foreign_key"):
			# FK generates a Resource reference to the target class
			type_str = fc["foreign_key"]
		var default_str = _get_default_value_string(field.get("default"), type_str)
		lines.append("@export var %s: %s = %s" % [field.name, type_str, default_str])

	lines.append("")
	return "\n".join(lines)


static func _get_default_value_string(value: Variant, type_string: String) -> String:
	match type_string:
		"int":
			return str(value if value != null else 0)
		"float":
			var v = value if value != null else 0.0
			var s = str(v)
			if not "." in s:
				s += ".0"
			return s
		"String":
			return '"%s"' % (value if value != null else "")
		"bool":
			return "true" if value else "false"
		"Color":
			if value is Color:
				return 'Color("%s")' % value.to_html()
			return "Color.WHITE"
		"Vector2":
			if value is Vector2:
				return "Vector2(%f, %f)" % [value.x, value.y]
			return "Vector2.ZERO"
		"Vector3":
			if value is Vector3:
				return "Vector3(%f, %f, %f)" % [value.x, value.y, value.z]
			return "Vector3.ZERO"
		"Texture2D":
			if value is Texture2D and not value.resource_path.is_empty():
				return 'preload("%s")' % value.resource_path
			return "null"
	if type_string.begins_with("Array"):
		return "[]"
	if type_string.begins_with("Dictionary"):
		return "{}"
	if "." in type_string:
		return "0"  # Enum types are ints, default to 0
	# Resource FK types and other object types default to null
	return "null"


# --- Helpers -----------------------------------------------------------------

## Ensure directory exists, creating it recursively if needed.
static func _ensure_directory(dir_path: String) -> Error:
	if DirAccess.dir_exists_absolute(dir_path):
		return OK
	return DirAccess.make_dir_recursive_absolute(dir_path)
