@tool
class_name FieldValidator
extends RefCounted

const GDSCRIPT_RESERVED := ["if", "elif", "else", "for", "while", "match",
	"break", "continue", "pass", "return", "class", "class_name", "extends",
	"is", "as", "self", "signal", "func", "static", "const", "enum", "var",
	"preload", "await", "yield", "assert", "void", "true", "false", "null",
	"not", "and", "or", "in"]

const DATAITEM_RESERVED := ["name", "id", "resource_path", "resource_name", "script",
	"resource_local_to_scene"]

static func validate_field_name(name: String, existing: Array[String] = []) -> String:
	var stripped_name := name.strip_edges()
	if stripped_name.is_empty():
		return "Field name cannot be empty"
	if not stripped_name.is_valid_identifier():
		return "Invalid GDScript identifier (use letters, numbers, and underscores, cannot start with a number)"
	if stripped_name in GDSCRIPT_RESERVED:
		return "'%s' is a GDScript reserved word" % stripped_name
	if stripped_name in DATAITEM_RESERVED:
		return "'%s' is reserved by DataItem" % stripped_name
	if stripped_name in existing:
		return "Duplicate field name: '%s'" % stripped_name
	return ""
