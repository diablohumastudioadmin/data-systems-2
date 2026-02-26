@tool
class_name SchemaCache
extends RefCounted

var _cache: Dictionary = {}  # {script_path: {script: GDScript, timestamp: int}}

func retrieve_script(script_path: String, load_func: Callable) -> GDScript:
	if not FileAccess.file_exists(script_path):
		return null
		
	var mod_time := FileAccess.get_modified_time(script_path)
	if _cache.has(script_path) and _cache[script_path].timestamp == mod_time:
		return _cache[script_path].script
		
	var script: GDScript = load_func.call(script_path)
	if script:
		_cache[script_path] = {
			"script": script,
			"timestamp": mod_time
		}
	return script

func invalidate(script_path: String) -> void:
	if _cache.has(script_path):
		_cache.erase(script_path)

func clear() -> void:
	_cache.clear()
