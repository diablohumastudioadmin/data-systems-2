@tool
class_name VisualResourcesEditorToolbar
extends DiablohumaStudioToolMenu

const VISUAL_RESOURCES_EDITOR_WINDOW_SCENE: PackedScene = preload("uid://b6ssn0jpljw4r")
var visual_resources_editor_window: VisualResourcesEditorWindow

var _listener: EditorFileSystemListener
var _state: VREStateManager

func _enter_tree() -> void:
	add_item("Launch Visual Editor", 0, KEY_F3)
	id_pressed.connect(_on_menu_id_pressed)

func _exit_tree() -> void:
	if is_instance_valid(visual_resources_editor_window):
		visual_resources_editor_window.queue_free()
	_cleanup()

func _on_menu_id_pressed(id: int):
	match id:
		0:
			open_visual_editor_window()

func open_visual_editor_window():
	if is_instance_valid(visual_resources_editor_window):
		visual_resources_editor_window.grab_focus()
		return

	# 1. Create infrastructure
	_listener = EditorFileSystemListener.new()
	var classes_repo: EditorClassesRepository = EditorClassesRepository.new(_listener)
	var resources_repo: EditorResourcesRepository = EditorResourcesRepository.new(_listener)

	# 2. Create state manager — wires itself to repos + listener in _init()
	_state = VREStateManager.new(classes_repo, resources_repo, _listener)

	# 3. Create window, inject state
	visual_resources_editor_window = VISUAL_RESOURCES_EDITOR_WINDOW_SCENE.instantiate()
	EditorInterface.get_base_control().add_child(visual_resources_editor_window)

	# These 2 calls are needed for correct functioning as when a Window inside a Window parented
	# scene that is in @tool mode, will show errors when reloading Godot with this scene opened
	visual_resources_editor_window.create_and_add_dialogs()
	visual_resources_editor_window.initialize(_state)

	# 4. Start listening AFTER everything is wired
	_listener.start()

	visual_resources_editor_window.close_requested.connect(func():
		_cleanup()
	)
	visual_resources_editor_window.popup_centered()

func _cleanup() -> void:
	if _listener:
		_listener.stop()
	if _state:
		_state.shutdown()
	_listener = null
	_state = null
	visual_resources_editor_window = null
