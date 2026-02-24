## Headless test for field constraints (Required + ForeignKey).
## Run: godot --headless --path . --script tests/test_constraints.gd
extends SceneTree


var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	_section("ResourceGenerator — FK enum type generation")
	# _generate_script_content is private static, but we can test via
	# generate_resource_class + read back the file contents.
	var test_dir := "res://tests/tmp_constraints/"
	DirAccess.make_dir_recursive_absolute(test_dir)

	var fields: Array[Dictionary] = [
		{"name": "hp", "type_string": "int", "default": 10},
		{"name": "zone_id", "type_string": "int", "default": 0},
		{"name": "label", "type_string": "String", "default": ""},
	]
	var constraints := {
		"zone_id": {"required": true, "foreign_key": "Zone"},
		"hp": {"required": true},
	}

	var err := ResourceGenerator.generate_resource_class(
		"TestMonster", fields, test_dir, constraints)
	_assert_eq(err, OK, "generate_resource_class returns OK")

	var content := FileAccess.get_file_as_string(test_dir.path_join("testmonster.gd"))
	_assert_true(not content.is_empty(), "generated file is not empty")
	_assert_true(content.contains("@export var zone_id: ZoneIds.Id = 0"),
		"FK field uses ZoneIds.Id enum type")
	_assert_true(content.contains("@export var hp: int = 10"),
		"non-FK required field keeps original type")
	_assert_true(content.contains("@export var label: String = \"\""),
		"non-constraint field is unchanged")
	_assert_true(content.contains("class_name TestMonster"),
		"class_name is correct")

	_section("ResourceGenerator — default values for enum/FK types")
	# A type containing "." should default to "0" (enum int)
	_assert_eq(ResourceGenerator.is_valid_type_string("Control.FocusMode"), true,
		"Control.FocusMode is valid")

	_section("ResourceGenerator — generate without constraints")
	var fields2: Array[Dictionary] = [
		{"name": "score", "type_string": "float", "default": 0.0},
	]
	err = ResourceGenerator.generate_resource_class("TestScore", fields2, test_dir)
	_assert_eq(err, OK, "generate without constraints returns OK")
	var content2 := FileAccess.get_file_as_string(test_dir.path_join("testscore.gd"))
	_assert_true(content2.contains("@export var score: float = 0.0"),
		"field without constraints generates normally")

	_section("DataTable — field_constraints storage")
	var table := DataTable.new()
	table.table_name = "Enemy"
	_assert_eq(table.field_constraints.is_empty(), true,
		"field_constraints defaults to empty")
	table.field_constraints = {"hp": {"required": true}, "zone": {"foreign_key": "Zone"}}
	_assert_eq(table.field_constraints.has("hp"), true,
		"can store 'hp' constraint")
	_assert_eq(table.field_constraints["hp"]["required"], true,
		"'hp' required == true")
	_assert_eq(table.field_constraints["zone"]["foreign_key"], "Zone",
		"'zone' foreign_key == 'Zone'")

	_section("DatabaseManager — constraint roundtrip (add + get)")
	var db_manager := DatabaseManager.new()
	db_manager.base_path = "res://tests/tmp_constraints/db/"
	# Ensure dirs exist
	DirAccess.make_dir_recursive_absolute(db_manager.structures_path)
	DirAccess.make_dir_recursive_absolute(db_manager.ids_path)

	# Create a fake database file so reload() doesn't error
	var db := Database.new()
	ResourceSaver.save(db, db_manager.database_path)
	db_manager.reload()

	var add_fields: Array[Dictionary] = [
		{"name": "damage", "type_string": "int", "default": 5},
	]
	var add_constraints := {"damage": {"required": true}}
	var success := db_manager.add_table("Weapon", add_fields, add_constraints)
	_assert_true(success, "add_table with constraints succeeds")

	var retrieved := db_manager.get_field_constraints("Weapon")
	_assert_eq(retrieved.has("damage"), true,
		"get_field_constraints returns 'damage'")
	_assert_eq(retrieved["damage"]["required"], true,
		"retrieved constraint 'required' is true")

	# Update table with new constraints
	var update_constraints := {"damage": {"required": true, "foreign_key": "Enemy"}}
	success = db_manager.update_table("Weapon", add_fields, update_constraints)
	_assert_true(success, "update_table with constraints succeeds")
	retrieved = db_manager.get_field_constraints("Weapon")
	_assert_eq(retrieved["damage"]["foreign_key"], "Enemy",
		"updated constraint has foreign_key")

	# Cleanup
	_cleanup_dir("res://tests/tmp_constraints/")

	# Summary
	print("")
	print("========================================")
	if _fail_count == 0:
		print("ALL %d TESTS PASSED" % _pass_count)
	else:
		print("%d PASSED, %d FAILED" % [_pass_count, _fail_count])
	print("========================================")

	quit(1 if _fail_count > 0 else 0)


func _cleanup_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full := path.path_join(file_name)
		if dir.current_is_dir():
			_cleanup_dir(full)
			DirAccess.remove_absolute(full)
		else:
			DirAccess.remove_absolute(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _section(name: String) -> void:
	print("\n--- %s ---" % name)


func _assert_true(value: bool, desc: String) -> void:
	if value:
		_pass(desc)
	else:
		_fail(desc, "expected true, got false")


func _assert_eq(a: Variant, b: Variant, desc: String) -> void:
	if a == b:
		_pass(desc)
	else:
		_fail(desc, "expected %s, got %s" % [b, a])


func _pass(desc: String) -> void:
	_pass_count += 1
	print("  PASS: %s" % desc)


func _fail(desc: String, detail: String) -> void:
	_fail_count += 1
	print("  FAIL: %s — %s" % [desc, detail])
