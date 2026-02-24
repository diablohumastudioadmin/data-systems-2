@tool
class_name LineEditAutocomplete
extends Control

## Generic LineEdit with autocomplete suggestions dropdown.
## Receives its suggestions and validation logic from a SuggestionProvider.
## The Panel overlay is created in code as a child of this Control.

signal text_committed(text: String)
signal validation_changed(has_error: bool)

@onready var line_edit: LineEdit = %LineEdit

@export var placeholder_text: String = "":
	set(value):
		placeholder_text = value
		if line_edit:
			line_edit.placeholder_text = value

var provider: SuggestionProvider
var has_error: bool = false
var last_error: String = ""

var _panel: Panel
var _list: ItemList

const _MAX_VISIBLE := 8
const _ITEM_H := 26.0


func _ready() -> void:
	_build_overlay()

	line_edit.placeholder_text = placeholder_text
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.focus_exited.connect(_on_focus_exited)
	line_edit.text_submitted.connect(func(_t): _on_focus_exited())


func _build_overlay() -> void:
	_panel = Panel.new()
	_panel.visible = false
	_panel.z_index = 100

	_list = ItemList.new()
	_list.focus_mode = Control.FOCUS_NONE
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_list.item_selected.connect(_on_suggestion_selected)
	_panel.add_child(_list)

	add_child(_panel)


# --- Public API -------------------------------------------------------------

func set_text(t: String) -> void:
	line_edit.text = t
	_validate(t)


func get_text() -> String:
	return line_edit.text.strip_edges()


func set_editable(value: bool) -> void:
	line_edit.editable = value


# --- Autocomplete -----------------------------------------------------------

func _on_text_changed(text: String) -> void:
	if not provider:
		return
	var suggestions := provider.get_suggestions(text)
	if suggestions.is_empty():
		_hide()
		return
	_show(suggestions)


func _show(suggestions: Array[String]) -> void:
	_list.clear()
	for s in suggestions:
		_list.add_item(s)

	var count := suggestions.size()
	var h := minf(count, _MAX_VISIBLE) * _ITEM_H
	var w := size.x
	_panel.size = Vector2(w, h)

	_panel.position = Vector2(0, size.y)
	_panel.visible = true


func _hide() -> void:
	if _panel:
		_panel.visible = false


func _on_suggestion_selected(index: int) -> void:
	var selected := _list.get_item_text(index)
	line_edit.text = selected
	line_edit.grab_focus()
	line_edit.set_caret_column(selected.length())
	if not selected.ends_with(", "):
		_hide()
		_commit()


# --- Validation & commit ----------------------------------------------------

func _on_focus_exited() -> void:
	_hide()
	_commit()


func _commit() -> void:
	var t := line_edit.text.strip_edges()
	_validate(t)
	text_committed.emit(t)


func _validate(t: String) -> void:
	if not provider or t.is_empty():
		line_edit.remove_theme_color_override("font_color")
		last_error = ""
		_set_error(false)
		return
	var error: String = provider.validate(t)
	if error.is_empty():
		line_edit.remove_theme_color_override("font_color")
		last_error = ""
		_set_error(false)
	else:
		line_edit.add_theme_color_override("font_color", Color.RED)
		last_error = error
		_set_error(true)


func _set_error(value: bool) -> void:
	if has_error != value:
		has_error = value
		validation_changed.emit(has_error)


# --- Keyboard navigation ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _panel or not _panel.visible:
		return
	if not line_edit.has_focus():
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
