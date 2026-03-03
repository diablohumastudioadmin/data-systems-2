@tool
class_name VREGResourceScanner
extends RefCounted

static func get_resource_classes() -> Array[Dictionary]:
	var classes: Array[Dictionary] = []
	
	# Add built-in Resource (if needed, but usually we just want user classes or specific ones)
	classes.append({
		"class": "Resource",
		"path": "",
		"base": "RefCounted",
		"icon": ""
	})
	
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var base_class: String = entry.get("base", "")
		var target_class_name: String = entry.get("class", "")
		# Check if it inherits from Resource
		if _inherits_from_resource(target_class_name, entry):
			classes.append(entry)
			
	return classes

static func _inherits_from_resource(target_class_name: String, entry: Dictionary) -> bool:
	var current_base = entry.get("base", "")
	while current_base != "" and current_base != "Resource" and current_base != "RefCounted" and current_base != "Object":
		var found = false
		for global_class in ProjectSettings.get_global_class_list():
			if global_class.get("class", "") == current_base:
				current_base = global_class.get("base", "")
				found = true
				break
		if not found:
			break
	return current_base == "Resource" or entry.get("base", "") == "Resource"

static func find_resources_of_type(target_class_name: String, script_path: String = "") -> Array[String]:
	var results: Array[String] = []
	_scan_dir_for_resources("res://", target_class_name, script_path, results)
	return results

static func _scan_dir_for_resources(path: String, target_class_name: String, script_path: String, results: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.begins_with(".") or file_name == "addons" or file_name == ".godot":
				# Skip hidden files, addons (optional, maybe want to search addons?), and .godot
				# Actually we might want to search addons if resources are there, but let's skip .godot
				if file_name == ".godot":
					file_name = dir.get_next()
					continue
			
			if dir.current_is_dir():
				_scan_dir_for_resources(path.path_join(file_name), target_class_name, script_path, results)
			else:
				if file_name.get_extension() == "tres" or file_name.get_extension() == "res":
					var file_path = path.path_join(file_name)
					
					# Load the resource to check its type
					var res := ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_REUSE)
					if res:
						var matches = false
						if script_path != "" and res.get_script() != null:
							if res.get_script().resource_path == script_path:
								matches = true
						elif target_class_name == "Resource" and res is Resource:
							matches = true
						
						# Check built-in class inheritance if it's not a script
						if not matches and script_path == "":
							if res.is_class(target_class_name):
								matches = true
								
						if matches:
							results.append(file_path)
			file_name = dir.get_next()
