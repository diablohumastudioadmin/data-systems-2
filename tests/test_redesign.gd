## Headless test for Phase 1 redesign: per-instance storage, Resource FK, no enums.
## Run: godot --headless --path . --script tests/test_redesign.gd
extends SceneTree


var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	var test_dir := "res://tests/tmp_redesign/"
	var structures_dir := test_dir.path_join("table_structures/")
	var instances_dir := test_dir.path_join("instances/")
	DirAccess.make_dir_recursive_absolute(structures_dir)
	DirAccess.make_dir_recursive_absolute(instances_dir)

	_test_resource_fk_generation(structures_dir)
	_test_constraint_consts(structures_dir)
	_test_storage_adapter(test_dir, structures_dir)
	_test_database_manager(test_dir, structures_dir)
	_test_id_generation_uniqueness()
	_test_lazy_loading(test_dir, structures_dir)
	_test_inheritance(test_dir, structures_dir)
	_test_migration(test_dir, structures_dir)

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


# =============================================================================
# Test: Resource FK type generation
# =============================================================================
func _test_resource_fk_generation(structures_dir: String) -> void:
	_section("ResourceGenerator — Resource FK type (not enum)")

	var fields: Array[Dictionary] = [
		{"name": "hp", "type_string": "int", "default": 10},
		{"name": "weapon", "type_string": "int", "default": 0},
	]
	var constraints := {
		"weapon": {"foreign_key": "Weapon"},
	}

	var err := ResourceGenerator.generate_resource_class(
		"TestEnemy", fields, structures_dir, constraints)
	_assert_eq(err, OK, "generate_resource_class returns OK")

	var content := FileAccess.get_file_as_string(structures_dir.path_join("testenemy.gd"))
	_assert_true(not content.is_empty(), "generated file is not empty")
	_assert_true(content.contains("@export var weapon: Weapon = null"),
		"FK field uses Resource type (Weapon), not enum (WeaponIds.Id)")
	_assert_true(content.contains("@export var hp: int = 10"),
		"non-FK field keeps original type")
	_assert_false(content.contains("Ids.Id"),
		"no enum reference in generated script")


# =============================================================================
# Test: _init() sets _required_fields + _fk_fields
# =============================================================================
func _test_constraint_consts(structures_dir: String) -> void:
	_section("ResourceGenerator — _init() constraint vars")

	var fields: Array[Dictionary] = [
		{"name": "health", "type_string": "int", "default": 100},
		{"name": "damage", "type_string": "int", "default": 5},
		{"name": "weapon", "type_string": "int", "default": 0},
	]
	var constraints := {
		"health": {"required": true},
		"damage": {"required": true},
		"weapon": {"foreign_key": "Weapon"},
	}

	ResourceGenerator.generate_resource_class(
		"TestConstMonster", fields, structures_dir, constraints)

	var content := FileAccess.get_file_as_string(
		structures_dir.path_join("testconstmonster.gd"))

	_assert_true(content.contains("func _init():"),
		"generated script has _init() method")
	_assert_true(content.contains('_required_fields = ["health", "damage"]'),
		"_init() sets _required_fields")
	_assert_true(content.contains('_fk_fields = {"weapon": "Weapon"}'),
		"_init() sets _fk_fields")


# =============================================================================
# Test: StorageAdapter per-instance save/load/delete
# =============================================================================
func _test_storage_adapter(test_dir: String, structures_dir: String) -> void:
	_section("StorageAdapter — per-instance save/load/delete")

	# Generate a script so we can create instances
	var fields: Array[Dictionary] = [
		{"name": "score", "type_string": "int", "default": 0},
	]
	ResourceGenerator.generate_resource_class("TestScore", fields, structures_dir)

	# Create a DataItem manually
	var script_path := structures_dir.path_join("testscore.gd")
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(script_path)
	# Strip class_name for anonymous script
	var lines := script.source_code.split("\n")
	var filtered: PackedStringArray = []
	for line in lines:
		if not line.strip_edges().begins_with("class_name"):
			filtered.append(line)
	script.source_code = "\n".join(filtered)
	script.reload()
	var item: DataItem = script.new()
	item.name = "player_one"
	item.id = 42
	item.set("score", 100)

	var storage := ResourceStorageAdapter.new()

	# Save
	var err := storage.save_instance(item, "TestScore", test_dir)
	_assert_eq(err, OK, "save_instance returns OK")

	var inst_dir := test_dir.path_join("instances/testscore/")
	_assert_true(DirAccess.dir_exists_absolute(inst_dir),
		"instances/testscore/ directory created")

	# Load
	var loaded: Array[DataItem] = storage.load_instances("TestScore", test_dir)
	_assert_eq(loaded.size(), 1, "load_instances returns 1 item")
	if loaded.size() > 0:
		_assert_eq(loaded[0].name, "player_one", "loaded item name matches")
		_assert_eq(loaded[0].id, 42, "loaded item id matches")

	# Delete
	err = storage.delete_instance(loaded[0] if loaded.size() > 0 else item, "TestScore", test_dir)
	_assert_eq(err, OK, "delete_instance returns OK")

	var after_delete: Array[DataItem] = storage.load_instances("TestScore", test_dir)
	_assert_eq(after_delete.size(), 0, "no items after delete")

	# Delete table dir
	err = storage.delete_table_instances_dir("TestScore", test_dir)
	_assert_eq(err, OK, "delete_table_instances_dir returns OK")
	_assert_false(DirAccess.dir_exists_absolute(inst_dir),
		"instances directory removed")


# =============================================================================
# Test: DatabaseManager — add table + add/remove instance
# =============================================================================
func _test_database_manager(test_dir: String, structures_dir: String) -> void:
	_section("DatabaseManager — filesystem-based table + instance CRUD")

	# Clean previous test artifacts
	_cleanup_dir(test_dir)
	DirAccess.make_dir_recursive_absolute(structures_dir)

	var db_manager := DatabaseManager.new()
	db_manager.base_path = test_dir
	# Don't call reload() — it would try migration on nonexistent database.tres

	# Add table
	var success := db_manager.add_table("Monster", [
		{"name": "hp", "type_string": "int", "default": 100},
		{"name": "attack", "type_string": "float", "default": 5.0},
	])
	_assert_true(success, "add_table 'Monster' succeeds")

	# Verify table exists via filesystem
	_assert_true(db_manager.has_table("Monster"), "has_table('Monster') is true")
	var names: Array[String] = db_manager.get_table_names()
	_assert_true("Monster" in names, "get_table_names() includes 'Monster'")

	# Verify instances directory was created
	var inst_dir := test_dir.path_join("instances/monster/")
	_assert_true(DirAccess.dir_exists_absolute(inst_dir),
		"instances/monster/ directory exists")

	# Get constraints from script consts
	var constraints_test_fields: Array[Dictionary] = [
		{"name": "dmg", "type_string": "int", "default": 0},
	]
	var constraints_test := {"dmg": {"required": true}}
	db_manager.add_table("WeaponTest", constraints_test_fields, constraints_test)
	var retrieved := db_manager.get_field_constraints("WeaponTest")
	_assert_true(retrieved.has("dmg"), "get_field_constraints returns 'dmg'")
	_assert_eq(retrieved["dmg"]["required"], true, "constraint required is true")

	# Add instance
	var item: DataItem = db_manager.add_instance("Monster", "Goblin")
	_assert_true(item != null, "add_instance returns non-null")
	if item:
		_assert_eq(item.name, "Goblin", "instance name is 'Goblin'")
		_assert_true(item.id != 0, "instance ID is non-zero (ResourceUID)")

	# Verify instance count
	_assert_eq(db_manager.get_instance_count("Monster"), 1,
		"get_instance_count is 1")

	# Verify get_by_id
	if item:
		var found: DataItem = db_manager.get_by_id("Monster", item.id)
		_assert_true(found != null, "get_by_id finds the item")
		if found:
			_assert_eq(found.name, "Goblin", "get_by_id returns correct item")

	# Remove by ID
	if item:
		var removed := db_manager.remove_instance("Monster", item.id)
		_assert_true(removed, "remove_instance by ID succeeds")
		_assert_eq(db_manager.get_instance_count("Monster"), 0,
			"instance count is 0 after removal")

	# Remove table
	success = db_manager.remove_table("Monster")
	_assert_true(success, "remove_table succeeds")
	_assert_false(db_manager.has_table("Monster"), "Monster no longer exists")


# =============================================================================
# Test: ID generation uniqueness
# =============================================================================
func _test_id_generation_uniqueness() -> void:
	_section("ID Generation — ResourceUID uniqueness")

	var ids: Array[int] = []
	for i in range(100):
		ids.append(ResourceUID.create_id())
	# Check all unique
	var unique := {}
	for id in ids:
		unique[id] = true
	_assert_eq(unique.size(), 100, "100 generated IDs are all unique")


# =============================================================================
# Test: Lazy loading
# =============================================================================
func _test_lazy_loading(test_dir: String, structures_dir: String) -> void:
	_section("DatabaseManager — lazy loading")

	_cleanup_dir(test_dir)
	DirAccess.make_dir_recursive_absolute(structures_dir)

	var db_manager := DatabaseManager.new()
	db_manager.base_path = test_dir

	db_manager.add_table("LazyTable", [
		{"name": "val", "type_string": "int", "default": 0},
	])

	db_manager.add_instance("LazyTable", "item1")
	db_manager.add_instance("LazyTable", "item2")

	# Clear instance cache to simulate fresh start
	db_manager.instances._instance_cache.clear()
	db_manager.instances._id_cache.clear()

	# Accessing should lazy-load
	var items: Array[DataItem] = db_manager.get_data_items("LazyTable")
	_assert_eq(items.size(), 2, "lazy-loaded 2 items from disk")
	_assert_true(db_manager.instances._instance_cache.has("LazyTable"),
		"instance cache populated after first access")


# =============================================================================
# Test: Inheritance still works
# =============================================================================
func _test_inheritance(test_dir: String, structures_dir: String) -> void:
	_section("Inheritance — parent/child/chain/polymorphic")

	_cleanup_dir(test_dir)
	DirAccess.make_dir_recursive_absolute(structures_dir)

	var db_manager := DatabaseManager.new()
	db_manager.base_path = test_dir

	# Add parent
	db_manager.add_table("Item", [
		{"name": "icon", "type_string": "String", "default": ""},
		{"name": "value", "type_string": "int", "default": 0},
	])

	# Add child
	db_manager.add_table("Weapon", [
		{"name": "damage", "type_string": "int", "default": 5},
	], {}, "Item")

	_assert_eq(db_manager.get_parent_table("Weapon"), "Item",
		"Weapon's parent is Item")
	_assert_eq(db_manager.get_parent_table("Item"), "",
		"Item has no parent")

	var children: Array[String] = db_manager.get_child_tables("Item")
	_assert_true("Weapon" in children, "Item's children include Weapon")

	# Own fields exclude parent fields
	var own_fields: Array[Dictionary] = db_manager.get_own_table_fields("Weapon")
	var own_names: Array[String] = []
	for f in own_fields:
		own_names.append(f.name)
	_assert_true("damage" in own_names, "own fields include 'damage'")
	_assert_false("icon" in own_names, "own fields exclude parent field 'icon'")

	# Inheritance chain
	var chain: Array[Dictionary] = db_manager.get_inheritance_chain("Weapon")
	_assert_eq(chain.size(), 3, "chain has 3 entries: DataItem, Item, Weapon")

	# Block deletion of parent
	var success := db_manager.remove_table("Item")
	_assert_false(success, "cannot delete Item (has child Weapon)")

	# Polymorphic queries
	db_manager.add_instance("Item", "Potion")
	db_manager.add_instance("Weapon", "Sword")

	var item_only: Array[DataItem] = db_manager.get_data_items("Item")
	_assert_eq(item_only.size(), 1, "get_data_items('Item') returns 1")

	var polymorphic: Array[DataItem] = db_manager.get_data_items_polymorphic("Item")
	_assert_eq(polymorphic.size(), 2, "polymorphic returns 2 (Item + Weapon)")


# =============================================================================
# Test: Migration from v1 database.tres
# =============================================================================
func _test_migration(test_dir: String, structures_dir: String) -> void:
	_section("MigrationHelper — v1 to v2 migration")

	_cleanup_dir(test_dir)
	DirAccess.make_dir_recursive_absolute(structures_dir)
	DirAccess.make_dir_recursive_absolute(test_dir.path_join("ids/"))

	# Create a v1 database.tres with old format
	var db := Database.new()
	var table := DataTable.new()
	table.table_name = "MigTest"
	table.field_constraints = {"score": {"required": true}}
	table.parent_table = ""

	# Generate the old-style script (with enum FK type)
	var fields: Array[Dictionary] = [
		{"name": "score", "type_string": "int", "default": 0},
	]
	ResourceGenerator.generate_resource_class("MigTest", fields, structures_dir)

	# Create an instance manually using the script
	var script := GDScript.new()
	var source := FileAccess.get_file_as_string(structures_dir.path_join("migtest.gd"))
	var lines := source.split("\n")
	var filtered: PackedStringArray = []
	for line in lines:
		if not line.strip_edges().begins_with("class_name"):
			filtered.append(line)
	script.source_code = "\n".join(filtered)
	script.reload()
	var item: DataItem = script.new()
	item.name = "test_item"
	item.id = 0
	item.set("score", 42)
	table.instances.append(item)
	table.next_id = 1

	db.add_table(table)
	ResourceSaver.save(db, test_dir.path_join("database.tres"))

	# Create a dummy ids file
	var ids_file := FileAccess.open(test_dir.path_join("ids/migtest_ids.gd"), FileAccess.WRITE)
	ids_file.store_string("class_name MigTestIds\nenum Id { TEST_ITEM = 0 }\n")
	ids_file.close()

	# Verify migration is needed
	_assert_true(MigrationHelper.needs_migration(test_dir),
		"needs_migration returns true when database.tres exists")

	# Run migration
	var storage := ResourceStorageAdapter.new()
	var result := MigrationHelper.migrate_v1_to_v2(test_dir, storage)
	_assert_true(result, "migrate_v1_to_v2 returns true")

	# Verify database.tres is deleted
	_assert_false(FileAccess.file_exists(test_dir.path_join("database.tres")),
		"database.tres deleted after migration")

	# Verify ids/ directory is deleted
	_assert_false(DirAccess.dir_exists_absolute(test_dir.path_join("ids/")),
		"ids/ directory deleted after migration")

	# Verify instances were saved as individual files
	var inst_dir := test_dir.path_join("instances/migtest/")
	_assert_true(DirAccess.dir_exists_absolute(inst_dir),
		"instances/migtest/ directory created")

	var migrated_items: Array[DataItem] = storage.load_instances("MigTest", test_dir)
	_assert_eq(migrated_items.size(), 1, "1 migrated instance found")
	if migrated_items.size() > 0:
		_assert_eq(migrated_items[0].name, "test_item", "migrated item name correct")
		_assert_true(migrated_items[0].id != 0,
			"migrated item has new time-hash ID (not old sequential)")

	# Verify script was regenerated with consts
	var new_content := FileAccess.get_file_as_string(structures_dir.path_join("migtest.gd"))
	_assert_true(new_content.contains("_required_fields"),
		"regenerated script sets _required_fields in _init()")

	# Verify migration is no longer needed
	_assert_false(MigrationHelper.needs_migration(test_dir),
		"needs_migration returns false after migration")


# =============================================================================
# Test helpers
# =============================================================================

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
