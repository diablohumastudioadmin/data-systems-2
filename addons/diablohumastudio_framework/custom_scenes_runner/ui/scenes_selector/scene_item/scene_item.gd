@tool
class_name SceneItem
extends HBoxContainer

signal scene_button_pressed
signal shortcut_button_pressed
signal remove_pressed

var run_scene_data: RunnerSceneData = RunnerSceneData.new()
var _capturing_shortcut: bool = false


func _ready() -> void:
	set_process_unhandled_key_input(false)
	_update_ui()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _capturing_shortcut:
		return
	if event is InputEventKey and event.pressed:
		run_scene_data.keyboard_shortcut = event.keycode
		_update_shortcut_button()
		_capturing_shortcut = false
		set_process_unhandled_key_input(false)

func set_data(new_data: RunnerSceneData) -> void:
	run_scene_data = new_data
	_update_ui()

func _update_ui() -> void:
	if not is_node_ready():
		return
	%NameEdit.text = run_scene_data.name
	_update_scene_button()
	_update_shortcut_button()

func _update_scene_button() -> void:
	%SceneButton.text = run_scene_data.scene_path.get_file() if run_scene_data.scene_path else "Select Scene..."

func _update_shortcut_button() -> void:
	if run_scene_data.keyboard_shortcut != KEY_NONE:
		%ShortcutButton.text = OS.get_keycode_string(run_scene_data.keyboard_shortcut)
	else:
		%ShortcutButton.text = "Set Shortcut..."

func _on_scene_button_pressed() -> void:
	%FileDialog.popup_centered()

func _on_shortcut_button_pressed() -> void:
	_capturing_shortcut = true
	%ShortcutButton.text = "Press a key..."
	set_process_unhandled_key_input(true)
	shortcut_button_pressed.emit()

func _on_remove_button_pressed() -> void:
	queue_free()

func _on_file_dialog_file_selected(path: String) -> void:
	run_scene_data.scene_path = path
	_update_scene_button()

func _on_name_edit_text_changed(new_text: String) -> void:
	run_scene_data.name = new_text
