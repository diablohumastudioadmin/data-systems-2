@tool
class_name VisualResourcesEditorGeminiToolbar
extends DiablohumaStudioToolMenu

const VisualResourcesEditorWindowPksc = preload("uid://cxe6plodx1eyy")
var visual_resources_editor_window: Window

func _enter_tree() -> void:
	add_item("Launch Visual Editor", 0, KEY_F4)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	pass

func _on_menu_id_pressed(id: int):
	match id:
		0:
			open_visual_editor_window()

func open_visual_editor_window():
	visual_resources_editor_window = VisualResourcesEditorWindowPksc.instantiate()
	EditorInterface.get_base_control().add_child(visual_resources_editor_window)
	visual_resources_editor_window.popup_centered()
