## Headless test for table inheritance.
## Run: godot --headless --path . --script tests/test_inheritance.gd
extends SceneTree


var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	var test_dir := "res://tests/tmp_inheritance/"
	var structures_dir := test_dir.path_join("table_structures/")
	DirAccess.make_dir_recursive_absolute(structures_dir)

	_section("ResourceGenerator — parent_class in script generation")

	# Generate parent table (extends DataItem)
	var parent_fields: Array[Dictionary] = [
		{"name": "icon", "type_string": "String", "default": ""},
		{"name": "value", "type_string": "int", "default": 0},
	]
	var err := ResourceGenerator.generate_resource_class(
		"TestItem", parent_fields, structures_dir)
	_assert_eq(err, OK, "generate parent class returns OK")

	var parent_content := FileAccess.get_file_as_string(
		structures_dir.path_join("testitem.gd"))
	_assert_true(parent_content.contains("extends DataItem"),
		"parent script extends DataItem")
	_assert_true(parent_content.contains("class_name TestItem"),
		"parent has correct class_name")

	# Generate child table (extends TestItem)
	var child_fields: Array[Dictionary] = [
		{"name": "damage", "type_string": "int", "default": 5},
		{"name": "range_val", "type_string": "float", "default": 1.0},
	]
	err = ResourceGenerator.generate_resource_class(
		"TestWeapon", child_fields, structures_dir, {}, "TestItem")
	_assert_eq(err, OK, "generate child class returns OK")

	var child_content := FileAccess.get_file_as_string(
		structures_dir.path_join("testweapon.gd"))
	_assert_true(child_content.contains('extends "%s"' % structures_dir.path_join("testitem.gd")),
		"child script extends parent via path (not DataItem)")
	_assert_true(child_content.contains("class_name TestWeapon"),
		"child has correct class_name")
	_assert_true(child_content.contains("@export var damage: int = 5"),
		"child has own field 'damage'")
	_assert_false(child_content.contains("icon"),
		"child does NOT contain parent field 'icon'")

	_section("DatabaseManager — add_table with parent")

	var db_manager := DatabaseManager.new()
	db_manager.base_path = test_dir
	DirAccess.make_dir_recursive_absolute(db_manager.structures_path)

	# Add parent table
	var success := db_manager.add_table("Item", [
		{"name": "icon", "type_string": "String", "default": ""},
		{"name": "value", "type_string": "int", "default": 0},
	])
	_assert_true(success, "add parent table 'Item' succeeds")

	# Add child table with parent
	success = db_manager.add_table("Weapon", [
		{"name": "damage", "type_string": "int", "default": 5},
	], {}, "Item")
	_assert_true(success, "add child table 'Weapon' with parent 'Item' succeeds")

	_section("DatabaseManager — get_parent_table / get_child_tables")

	_assert_eq(db_manager.get_parent_table("Weapon"), "Item",
		"Weapon's parent is Item")
	_assert_eq(db_manager.get_parent_table("Item"), "",
		"Item has no parent")

	var children: Array[String] = db_manager.get_child_tables("Item")
	_assert_true("Weapon" in children,
		"Item's children include Weapon")
	_assert_eq(db_manager.get_child_tables("Weapon").size(), 0,
		"Weapon has no children")

	_section("DatabaseManager — get_own_table_fields excludes parent fields")

	var own_fields: Array[Dictionary] = db_manager.get_own_table_fields("Weapon")
	var own_names: Array[String] = []
	for f in own_fields:
		own_names.append(f.name)
	_assert_true("damage" in own_names,
		"own fields include 'damage'")
	_assert_false("icon" in own_names,
		"own fields exclude parent field 'icon'")
	_assert_false("value" in own_names,
		"own fields exclude parent field 'value'")

	# Parent's own fields should include everything (no parent to subtract)
	var item_own: Array[Dictionary] = db_manager.get_own_table_fields("Item")
	var item_names: Array[String] = []
	for f in item_own:
		item_names.append(f.name)
	_assert_true("icon" in item_names,
		"Item own fields include 'icon'")
	_assert_true("value" in item_names,
		"Item own fields include 'value'")

	_section("DatabaseManager — get_inheritance_chain")

	var chain: Array[Dictionary] = db_manager.get_inheritance_chain("Weapon")
	_assert_eq(chain.size(), 3,
		"chain has 3 entries: DataItem, Item, Weapon")
	_assert_eq(chain[0].table_name, "DataItem",
		"chain[0] is DataItem")
	_assert_eq(chain[1].table_name, "Item",
		"chain[1] is Item")
	_assert_eq(chain[2].table_name, "Weapon",
		"chain[2] is Weapon")

	_section("DatabaseManager — block deletion of parent table")

	success = db_manager.remove_table("Item")
	_assert_false(success,
		"cannot delete Item (has child Weapon)")

	_section("DatabaseManager — circular inheritance prevention")

	# Try to add a table that would create a cycle: Item → Weapon → Item
	success = db_manager.add_table("SubWeapon", [
		{"name": "sub", "type_string": "String", "default": ""},
	], {}, "Weapon")
	_assert_true(success, "add SubWeapon (child of Weapon) succeeds")

	# Try update_table to create cycle: Item's parent = SubWeapon
	success = db_manager.update_table("Item", [
		{"name": "icon", "type_string": "String", "default": ""},
		{"name": "value", "type_string": "int", "default": 0},
	], {}, "SubWeapon")
	_assert_false(success,
		"cannot set Item parent to SubWeapon (cycle: Item→Weapon→SubWeapon→Item)")

	_section("DatabaseManager — is_descendant_of")

	_assert_true(db_manager.is_descendant_of("Weapon", "Item"),
		"Weapon is descendant of Item")
	_assert_true(db_manager.is_descendant_of("SubWeapon", "Item"),
		"SubWeapon is descendant of Item")
	_assert_false(db_manager.is_descendant_of("Item", "Weapon"),
		"Item is NOT descendant of Weapon")

	_section("DatabaseManager — polymorphic queries")

	db_manager.add_instance("Item", "Potion")
	db_manager.add_instance("Weapon", "Sword")
	db_manager.add_instance("SubWeapon", "MagicSword")

	var item_only: Array[DataItem] = db_manager.get_data_items("Item")
	_assert_eq(item_only.size(), 1,
		"get_data_items('Item') returns 1 (non-polymorphic)")

	var polymorphic: Array[DataItem] = db_manager.get_data_items_polymorphic("Item")
	_assert_eq(polymorphic.size(), 3,
		"get_data_items_polymorphic('Item') returns 3 (Item + Weapon + SubWeapon)")

	var weapon_poly: Array[DataItem] = db_manager.get_data_items_polymorphic("Weapon")
	_assert_eq(weapon_poly.size(), 2,
		"get_data_items_polymorphic('Weapon') returns 2 (Weapon + SubWeapon)")

	# Cleanup
	_cleanup_dir(test_dir)

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


func _assert_false(value: bool, desc: String) -> void:
	if not value:
		_pass(desc)
	else:
		_fail(desc, "expected false, got true")


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
