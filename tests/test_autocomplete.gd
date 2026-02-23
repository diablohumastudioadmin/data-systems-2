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

	_section("TypeSuggestionProvider.get_suggestions — Enum context")
	_assert_contains(provider.get_suggestions("Control.Focus"), "Control.FocusMode",
		"'Control.Focus' should suggest 'Control.FocusMode'")
	_assert_contains(provider.get_suggestions("Control."), "Control.FocusMode",
		"'Control.' should suggest 'Control.FocusMode'")
	_assert_contains(provider.get_suggestions("Node.Process"), "Node.ProcessMode",
		"'Node.Process' should suggest 'Node.ProcessMode'")
	_assert_empty(provider.get_suggestions("Control.ZZZNonExistent"),
		"'Control.ZZZNonExistent' should return no suggestions")

	_section("TypeSuggestionProvider.validate — valid types return empty")
	_assert_valid(provider.validate("int"), "'int'")
	_assert_valid(provider.validate("float"), "'float'")
	_assert_valid(provider.validate("String"), "'String'")
	_assert_valid(provider.validate("bool"), "'bool'")
	_assert_valid(provider.validate("Array[int]"), "'Array[int]'")
	_assert_valid(provider.validate("Array[String]"), "'Array[String]'")
	_assert_valid(provider.validate("Dictionary[String, int]"),
		"'Dictionary[String, int]'")

	_section("TypeSuggestionProvider.validate — invalid types return error")
	_assert_error(provider.validate("notavalidtype"), "not a valid",
		"'notavalidtype' returns error with 'not a valid'")
	_assert_error(provider.validate("Array[notvalid]"), "Invalid element type",
		"'Array[notvalid]' returns error about element type")

	_section("TypeSuggestionProvider.validate — enums")
	_assert_valid(provider.validate("Control.FocusMode"),
		"'Control.FocusMode' (engine enum)")
	_assert_error(provider.validate("Control.Fo"), "Unknown enum",
		"'Control.Fo' returns error about unknown enum")
	_assert_error(provider.validate("Control."), "Expected enum name",
		"'Control.' returns error about expected enum name")
	_assert_error(provider.validate("Control.NonExistentEnum"), "Unknown enum",
		"'Control.NonExistentEnum' returns error about unknown enum")
	_assert_valid(provider.validate("Node.ProcessMode"),
		"'Node.ProcessMode' (engine enum)")

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


## validate() returns "" for valid, non-empty error for invalid
func _assert_valid(error: String, desc: String) -> void:
	if error.is_empty():
		_pass("%s is valid" % desc)
	else:
		_fail("%s is valid" % desc, "got error: '%s'" % error)


func _assert_error(error: String, expected_substring: String, desc: String) -> void:
	if not error.is_empty() and error.to_lower().contains(expected_substring.to_lower()):
		_pass(desc)
	elif error.is_empty():
		_fail(desc, "expected error containing '%s', got empty (valid)" % expected_substring)
	else:
		_fail(desc, "expected error containing '%s', got '%s'" % [expected_substring, error])


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
