@tool
class_name TypeAutocomplete
extends Control

## Reusable GDScript type-string input with autocomplete suggestions panel.
## Uses a Panel overlay attached to the editor base control (same OS window)
## to avoid focus-stealing issues of PopupPanel on macOS.
## Emits type_committed when the user finishes editing (focus_exited, Enter,
## or clicking a suggestion).

signal type_committed(type_string: String, is_valid: bool)

@onready var type_edit: LineEdit = %TypeEdit

# Floating overlay — created in code, parented to EditorInterface.get_base_control()
# so it shares the same OS window as the LineEdit (no focus stealing on macOS).
var _panel: Panel
var _list: ItemList

var _engine_classes: Array[String] = []

const _MAX_VISIBLE := 8
const _ITEM_H := 26.0


func _ready() -> void:
	# Cache engine class list once — 700+ entries, too expensive per keystroke
	for cls: String in ClassDB.get_class_list():
		_engine_classes.append(cls)
	_engine_classes.sort()

	_build_overlay()

	type_edit.text_changed.connect(_on_text_changed)
	type_edit.focus_exited.connect(_on_focus_exited)
	type_edit.text_submitted.connect(func(_t): _on_focus_exited())


func _build_overlay() -> void:
	_panel = Panel.new()
	_panel.visible = false
	# High z_index so the panel renders over sibling controls in the same parent
	_panel.z_index = 100

	_list = ItemList.new()
	# FOCUS_NONE: clicking suggestions does not steal keyboard focus from TypeEdit,
	# so focus_exited never fires while the user is clicking a suggestion.
	_list.focus_mode = Control.FOCUS_NONE
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list.item_selected.connect(_on_suggestion_selected)
	_panel.add_child(_list)

	# Add as child of this Control — same coordinate space, no screen conversion needed.
	# _panel is freed automatically when the TypeAutocomplete node is freed.
	add_child(_panel)


# --- Public API -------------------------------------------------------------

func set_type_string(ts: String) -> void:
	type_edit.text = ts
	_validate(ts)


func get_type_string() -> String:
	return type_edit.text.strip_edges()


# --- Autocomplete -----------------------------------------------------------

func _on_text_changed(text: String) -> void:
	var suggestions := _get_suggestions(text)
	if suggestions.is_empty():
		_hide()
		return
	_show(suggestions)


func _get_suggestions(typed: String) -> Array[String]:
	var ctx := _get_context(typed)
	# Empty top-level input — don't spam every primitive
	if ctx.partial.is_empty() and ctx.prefix.is_empty():
		return []
	var lower: String = ctx.partial.to_lower()
	var results: Array[String] = []

	# a) primitives
	for p: String in ResourceGenerator.PRIMITIVE_TYPES:
		if p.to_lower().begins_with(lower):
			results.append(ctx.prefix + p + ctx.suffix)

	# b) user classes (ProjectSettings keeps this up-to-date without a scan)
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = entry.get("class", "")
		if cls.to_lower().begins_with(lower):
			results.append(ctx.prefix + cls + ctx.suffix)

	# c) engine classes — only when partial >= 2 chars (ClassDB has 700+ entries)
	if ctx.partial.length() >= 2:
		for cls: String in _engine_classes:
			if cls.to_lower().begins_with(lower) \
					and cls not in ResourceGenerator.PRIMITIVE_TYPES:
				results.append(ctx.prefix + cls + ctx.suffix)

	if results.size() > 50:
		results.resize(50)
	return results


## Returns {prefix, suffix, partial} describing the current completion context.
## Examples:
##   "Le"                → {prefix:"",              suffix:"",   partial:"Le"}
##   "Array[Le"          → {prefix:"Array[",        suffix:"]",  partial:"Le"}
##   "Dictionary[St"     → {prefix:"Dictionary[",   suffix:", ", partial:"St"}
##   "Dictionary[S, in"  → {prefix:"Dictionary[S, " suffix:"]",  partial:"in"}
func _get_context(typed: String) -> Dictionary:
	if typed.begins_with("Array[") and not typed.ends_with("]"):
		return {prefix = "Array[", suffix = "]", partial = typed.substr(6)}
	if typed.begins_with("Dictionary[") and not typed.ends_with("]"):
		var inner := typed.substr(11)
		var comma := ResourceGenerator.find_top_level_comma(inner)
		if comma < 0:
			# Completing key; suffix ", " keeps popup open for value entry
			return {prefix = "Dictionary[", suffix = ", ", partial = inner}
		return {
			prefix = "Dictionary[" + inner.substr(0, comma + 1) + " ",
			suffix = "]",
			partial = inner.substr(comma + 1).strip_edges()
		}
	return {prefix = "", suffix = "", partial = typed}


func _show(suggestions: Array[String]) -> void:
	_list.clear()
	for s in suggestions:
		_list.add_item(s)

	var count := suggestions.size()
	# Size panel to fit items exactly — no scrollbar when count <= _MAX_VISIBLE
	# _list fills panel automatically via PRESET_FULL_RECT anchors
	var h := minf(count, _MAX_VISIBLE) * _ITEM_H
	var w := type_edit.size.x
	_panel.size = Vector2(w, h)

	# Position directly below this control — same coordinate space, no conversion needed
	_panel.position = Vector2(0, size.y)
	_panel.visible = true


func _hide() -> void:
	if _panel:
		_panel.visible = false


func _on_suggestion_selected(index: int) -> void:
	var selected := _list.get_item_text(index)
	type_edit.text = selected
	type_edit.grab_focus()
	type_edit.set_caret_column(selected.length())
	# Dictionary key ends with ", " → text_changed reopens popup for value entry
	# Everything else → close popup and commit
	if not selected.ends_with(", "):
		_hide()
		_commit()


# --- Validation & commit ----------------------------------------------------

func _on_focus_exited() -> void:
	_hide()
	_commit()


func _commit() -> void:
	var ts := type_edit.text.strip_edges()
	_validate(ts)
	var valid := ts.is_empty() or ResourceGenerator.is_valid_type_string(ts)
	type_committed.emit(ts, valid)


func _validate(ts: String) -> void:
	var valid := ts.is_empty() or ResourceGenerator.is_valid_type_string(ts)
	if valid:
		type_edit.remove_theme_color_override("font_color")
	else:
		type_edit.add_theme_color_override("font_color", Color.RED)


# --- Keyboard navigation ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _panel or not _panel.visible:
		return
	if not type_edit.has_focus():
		return
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_DOWN:
			_select_offset(1)
			accept_event()
		KEY_UP:
			_select_offset(-1)
			accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			var sel := _list.get_selected_items()
			if sel.size() > 0:
				_on_suggestion_selected(sel[0])
			accept_event()
		KEY_ESCAPE:
			_hide()
			accept_event()


func _select_offset(delta: int) -> void:
	var sel := _list.get_selected_items()
	var cur := sel[0] if sel.size() > 0 else -1
	var next := clampi(cur + delta, 0, _list.item_count - 1)
	_list.select(next)
	_list.ensure_current_is_visible()
