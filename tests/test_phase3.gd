extends SceneTree

var _pass_count := 0
var _fail_count := 0

func _init() -> void:
	print("Running Phase 3 tests...")
	
	_test_field_validator()
	_test_schema_cache()
	_test_fk_rename_update()
	
	print("")
	print("========================================")
	if _fail_count == 0:
		print("ALL %d TESTS PASSED" % _pass_count)
	else:
		print("%d PASSED, %d FAILED" % [_pass_count, _fail_count])
	print("========================================")

	quit(1 if _fail_count > 0 else 0)

func _assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if typeof(actual) == typeof(expected) and actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		printerr("FAIL: %s (Expected: %s, Actual: %s)" % [msg, expected, actual])

func _assert_true(actual: bool, msg: String) -> void:
	_assert_eq(actual, true, msg)

func _test_field_validator() -> void:
	print("--- Test FieldValidator ---")
	var validator = preload("res://addons/diablohumastudio/database_manager/utils/field_validator.gd")
	
	_assert_eq(validator.validate_field_name(""), "Field name cannot be empty", "Empty name")
	_assert_eq(validator.validate_field_name("1invalid"), "Invalid GDScript identifier (use letters, numbers, and underscores, cannot start with a number)", "Starts with number")
	_assert_eq(validator.validate_field_name("class"), "'class' is a GDScript reserved word", "Reserved GDScript")
	_assert_eq(validator.validate_field_name("id"), "'id' is reserved by DataItem", "Reserved DataItem")
	_assert_eq(validator.validate_field_name("valid_name", ["existing", "valid_name"]), "Duplicate field name: 'valid_name'", "Duplicate name")
	_assert_eq(validator.validate_field_name("valid_name", ["existing"]), "", "Valid name")

func _test_schema_cache() -> void:
	print("--- Test SchemaCache ---")
	var cache = preload("res://addons/diablohumastudio/database_manager/utils/schema_cache.gd").new()
	var load_count = [0]
	
	var test_dir = "res://tests/tmp_phase3/"
	DirAccess.make_dir_recursive_absolute(test_dir)
	var test_file = test_dir.path_join("dummy.gd")
	
	var f = FileAccess.open(test_file, FileAccess.WRITE)
	f.store_string("extends Node
")
	f.close()
	
	var load_func = func(_path: String):
		load_count[0] += 1
		var script = GDScript.new()
		script.source_code = "extends Node
var test = 1
"
		script.reload()
		return script

	var s1 = cache.retrieve_script(test_file, load_func)
	_assert_eq(load_count[0], 1, "Load func called once")
	
	var s2 = cache.retrieve_script(test_file, load_func)
	_assert_eq(load_count[0], 1, "Load func not called second time (cached)")
	_assert_eq(s1, s2, "Cached script returned")
	
	cache.invalidate(test_file)
	var s3 = cache.retrieve_script(test_file, load_func)
	_assert_eq(load_count[0], 2, "Load func called after invalidate")
	
	cache.clear()
	var s4 = cache.retrieve_script(test_file, load_func)
	_assert_eq(load_count[0], 3, "Load func called after clear")
	
	# Cleanup
	DirAccess.remove_absolute(test_file)
	DirAccess.remove_absolute(test_dir)

func _test_fk_rename_update() -> void:
	print("--- Test FK Rename Update ---")
	var test_dir = "res://tests/tmp_phase3_db/"
	DirAccess.make_dir_recursive_absolute(test_dir.path_join("table_structures/"))
	DirAccess.make_dir_recursive_absolute(test_dir.path_join("instances/"))
	
	var sm = SchemaManager.new(test_dir)
	var storage = preload("res://addons/diablohumastudio/database_manager/core/storage/resource_storage_adapter.gd").new()
	var im = preload("res://addons/diablohumastudio/database_manager/core/instance_manager.gd").new(storage, sm, test_dir)
	sm.instance_manager = im
	
	# Add table Weapon
	sm.add_table("Weapon", [{"name": "damage", "type_string": "int", "default": 10}])
	
	# Add table Character referencing Weapon
	# We use "Resource" as the type string in headless tests because Godot headless won't 
	# immediately register the new class_name Weapon into the global class DB.
	sm.add_table("Character", [{"name": "weapon", "type_string": "Resource", "default": null}], {"weapon": {"foreign_key": "Weapon"}})
	
	var constraints_before = sm.get_field_constraints("Character")
	_assert_eq(constraints_before.get("weapon", {}).get("foreign_key"), "Weapon", "Character references Weapon")
	
	# Rename Weapon to Item
	sm.rename_table("Weapon", "Item", [{"name": "damage", "type_string": "int", "default": 10}])
	
	var constraints_after = sm.get_field_constraints("Character")
	_assert_eq(constraints_after.get("weapon", {}).get("foreign_key"), "Item", "Character references Item after rename")
	
	# Verify script was updated
	var char_script_path = test_dir.path_join("table_structures/character.gd")
	var char_source = FileAccess.get_file_as_string(char_script_path)
	_assert_true(char_source.find("\"Weapon\"") == -1, "Old table name removed from script")
	_assert_true(char_source.find("\"Item\"") != -1, "New table name present in script")
	
	# Cleanup
	sm.remove_table("Character")
	sm.remove_table("Item")
	DirAccess.remove_absolute(test_dir.path_join("instances/"))
	DirAccess.remove_absolute(test_dir.path_join("table_structures/"))
	DirAccess.remove_absolute(test_dir)
