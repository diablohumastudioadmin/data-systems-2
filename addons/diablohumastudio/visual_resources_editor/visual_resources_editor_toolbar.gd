@tool
class_name VisualResourcesEditorToolbar
extends DiablohumaStudioToolMenu

const VISUAL_RESOURCES_EDITOR_WINDOW_SCENE: PackedScene = preload("uid://b6ssn0jpljw4r")
var visual_resources_editor_window : VisualResourcesEditorWindow 

func _enter_tree() -> void:
	add_item("Launch Visual Editor", 0, KEY_F3)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	if is_instance_valid(visual_resources_editor_window):
		visual_resources_editor_window.queue_free()
		visual_resources_editor_window = null

func _on_menu_id_pressed(id: int):
	match id:
		0:
			open_visual_editor_window()

func open_visual_editor_window():
	if is_instance_valid(visual_resources_editor_window):
		visual_resources_editor_window.grab_focus()
		return
	visual_resources_editor_window = VISUAL_RESOURCES_EDITOR_WINDOW_SCENE.instantiate()
	EditorInterface.get_base_control().add_child(visual_resources_editor_window)
	
	# This 2 functions are needed for correct functioning as when a Window inside a Window parented
	# scene that is in @tool mode, will show errors when reloading Godot with this scene opened 
	visual_resources_editor_window.create_and_add_dialogs()
	visual_resources_editor_window.connect_components()
	
	visual_resources_editor_window.close_requested.connect(func():
		visual_resources_editor_window = null
	)
	visual_resources_editor_window.popup_centered()
