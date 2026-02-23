## Headless test for TypeSuggestionProvider and ResourceGenerator validation.
## Run: godot --headless --path . --script tests/test_autocomplete.gd
extends SceneTree


var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	var provider := TypeSuggestionProvider.new()

	_section("TypeSuggestionProvider.get_suggestions")
	_assert_contains(provider.get_suggestions("flo"), "float",
		"'flo' should suggest 'float'")
	_assert_contains(provider.get_suggestions("in"), "int",
		"'in' should suggest 'int'")
	_assert_contains(provider.get_suggestions("Str"), "String",
		"'Str' should suggest 'String'")
	_assert_contains(provider.get_suggestions("bo"), "bool",
		"'bo' should suggest 'bool'")
	_assert_empty(provider.get_suggestions(""),
		"empty string should return no suggestions")

	_section("TypeSuggestionProvider.get_suggestions — Array context")
	_assert_contains(provider.get_suggestions("Array[in"), "Array[int]",
		"'Array[in' should suggest 'Array[int]'")
	_assert_contains(provider.get_suggestions("Array[Str"), "Array[String]",
		"'Array[Str' should suggest 'Array[String]'")

	_section("TypeSuggestionProvider.get_suggestions — Dictionary context")
	_assert_contains(provider.get_suggestions("Dictionary[St"), "Dictionary[String, ",
		"'Dictionary[St' should suggest 'Dictionary[String, '")
	_assert_contains(provider.get_suggestions("Dictionary[String, in"), "Dictionary[String, int]",
		"'Dictionary[String, in' should suggest 'Dictionary[String, int]'")

	_section("TypeSuggestionProvider.validate")
	_assert_true(provider.validate("int"), "'int' is valid")
	_assert_true(provider.validate("float"), "'float' is valid")
	_assert_true(provider.validate("String"), "'String' is valid")
	_assert_true(provider.validate("bool"), "'bool' is valid")
	_assert_true(provider.validate("Array[int]"), "'Array[int]' is valid")
	_assert_true(provider.validate("Array[String]"), "'Array[String]' is valid")
	_assert_true(provider.validate("Dictionary[String, int]"),
		"'Dictionary[String, int]' is valid")
	_assert_false(provider.validate("notavalidtype"),
		"'notavalidtype' is invalid")
	_assert_false(provider.validate("Array[notvalid]"),
		"'Array[notvalid]' is invalid")

	_section("TypeSuggestionProvider.validate — enums")
	_assert_true(provider.validate("Control.FocusMode"),
		"'Control.FocusMode' is valid (engine enum)")
	_assert_false(provider.validate("Control.Fo"),
		"'Control.Fo' is invalid (partial enum name)")
	_assert_false(provider.validate("Control."),
		"'Control.' is invalid (empty enum part)")
	_assert_false(provider.validate("Control.NonExistentEnum"),
		"'Control.NonExistentEnum' is invalid")
	_assert_true(provider.validate("Node.ProcessMode"),
		"'Node.ProcessMode' is valid (engine enum)")

	_section("ResourceGenerator.is_valid_type_string")
	_assert_true(ResourceGenerator.is_valid_type_string("int"),
		"is_valid_type_string('int')")
	_assert_true(ResourceGenerator.is_valid_type_string("Vector2"),
		"is_valid_type_string('Vector2')")
	_assert_true(ResourceGenerator.is_valid_type_string("Color"),
		"is_valid_type_string('Color')")
	_assert_true(ResourceGenerator.is_valid_type_string("Node"),
		"is_valid_type_string('Node') — engine class")
	_assert_true(ResourceGenerator.is_valid_type_string("Resource"),
		"is_valid_type_string('Resource') — engine class")
	_assert_false(ResourceGenerator.is_valid_type_string("FakeType123"),
		"is_valid_type_string('FakeType123') — invalid")

	_section("ResourceGenerator.get_editor_type")
	_assert_eq(ResourceGenerator.get_editor_type("int"),
		ResourceGenerator.DefaultEditorType.INT, "int → INT editor")
	_assert_eq(ResourceGenerator.get_editor_type("float"),
		ResourceGenerator.DefaultEditorType.FLOAT, "float → FLOAT editor")
	_assert_eq(ResourceGenerator.get_editor_type("String"),
		ResourceGenerator.DefaultEditorType.STRING, "String → STRING editor")
	_assert_eq(ResourceGenerator.get_editor_type("bool"),
		ResourceGenerator.DefaultEditorType.BOOL, "bool → BOOL editor")
	_assert_eq(ResourceGenerator.get_editor_type("Color"),
		ResourceGenerator.DefaultEditorType.COLOR, "Color → COLOR editor")
	_assert_eq(ResourceGenerator.get_editor_type("Array[int]"),
		ResourceGenerator.DefaultEditorType.NONE, "Array[int] → NONE editor")

	# Summary
	print("")
	print("========================================")
	if _fail_count == 0:
		print("ALL %d TESTS PASSED" % _pass_count)
	else:
		print("%d PASSED, %d FAILED" % [_pass_count, _fail_count])
	print("========================================")

	quit(1 if _fail_count > 0 else 0)


func _section(name: String) -> void:
	print("\n--- %s ---" % name)


func _assert_contains(arr: Array[String], expected: String, desc: String) -> void:
	if expected in arr:
		_pass(desc)
	else:
		_fail(desc, "expected '%s' in %s" % [expected, arr])


func _assert_empty(arr: Array[String], desc: String) -> void:
	if arr.is_empty():
		_pass(desc)
	else:
		_fail(desc, "expected empty, got %s" % [arr])


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
