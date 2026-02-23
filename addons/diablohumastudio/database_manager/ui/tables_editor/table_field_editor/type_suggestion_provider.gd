@tool
class_name TypeSuggestionProvider
extends SuggestionProvider

## SuggestionProvider for GDScript type strings.
## Returns matching primitives, user classes, and engine classes.
## Handles Array[T] and Dictionary[K, V] context parsing.

var _engine_classes: Array[String] = []


func _init() -> void:
	for cls: String in ClassDB.get_class_list():
		_engine_classes.append(cls)
	_engine_classes.sort()


func get_suggestions(typed: String) -> Array[String]:
	var ctx := _get_context(typed)
	if ctx.partial.is_empty() and ctx.prefix.is_empty():
		return []
	var lower: String = ctx.partial.to_lower()
	var results: Array[String] = []

	# a) primitives
	for p: String in ResourceGenerator.PRIMITIVE_TYPES:
		if p.to_lower().begins_with(lower):
			results.append(ctx.prefix + p + ctx.suffix)

	# b) user classes
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if cls.to_lower().begins_with(lower):
			results.append(ctx.prefix + cls + ctx.suffix)

	# c) engine classes — only when partial >= 2 chars (700+ entries)
	if ctx.partial.length() >= 2:
		for cls: String in _engine_classes:
			if cls.to_lower().begins_with(lower) \
					and cls not in ResourceGenerator.PRIMITIVE_TYPES:
				results.append(ctx.prefix + cls + ctx.suffix)

	# d) enums — when partial contains a dot (e.g. "Control." or "Control.Fo")
	if "." in ctx.partial:
		var dot: int = ctx.partial.find(".")
		var class_part: String = ctx.partial.substr(0, dot)
		var enum_partial: String = ctx.partial.substr(dot + 1).to_lower()
		var enum_names: Array[String] = _get_enum_names(class_part)
		for en: String in enum_names:
			if enum_partial.is_empty() or en.to_lower().begins_with(enum_partial):
				results.append(ctx.prefix + class_part + "." + en + ctx.suffix)

	if results.size() > 50:
		results.resize(50)
	return results


func validate(text: String) -> String:
	return ResourceGenerator.validate_type_string(text)


## Returns {prefix, suffix, partial} describing the current completion context.
func _get_context(typed: String) -> Dictionary:
	if typed.begins_with("Array[") and not typed.ends_with("]"):
		return {prefix = "Array[", suffix = "]", partial = typed.substr(6)}
	if typed.begins_with("Dictionary[") and not typed.ends_with("]"):
		var inner := typed.substr(11)
		var comma := ResourceGenerator.find_top_level_comma(inner)
		if comma < 0:
			return {prefix = "Dictionary[", suffix = ", ", partial = inner}
		return {
			prefix = "Dictionary[" + inner.substr(0, comma + 1) + " ",
			suffix = "]",
			partial = inner.substr(comma + 1).strip_edges()
		}
	return {prefix = "", suffix = "", partial = typed}


## Returns enum names for a class (engine or user-defined).
func _get_enum_names(class_name_str: String) -> Array[String]:
	var names: Array[String] = []
	if ClassDB.class_exists(class_name_str):
		for en: String in ClassDB.class_get_enum_list(class_name_str, true):
			names.append(en)
		return names
	# User-defined class — check script constants (enums are Dictionary constants)
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class", "") == class_name_str:
			var script: GDScript = load(entry.get("path", ""))
			if script:
				for key: String in script.get_script_constant_map():
					if script.get_script_constant_map()[key] is Dictionary:
						names.append(key)
			break
	return names
