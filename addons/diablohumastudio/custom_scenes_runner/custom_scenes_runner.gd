@tool
class_name CustomScenesRunner
extends PopupMenu

const SELECT_SCENES_ITEM_ID := 1000

var select_scenes_popup: PackedScene = preload("uid://dlfttbd1xdwe8")
var scenes: Array[RunSceneData] = []
var saved_scenes_resource_path: String

func _enter_tree() -> void:
	saved_scenes_resource_path = _get_scenes_resource_path()
	_load_scenes()
	_rebuild_menu()
	id_pressed.connect(_on_menu_id_pressed)


func _get_scenes_resource_path() -> String:
	var script_path: String = get_script().resource_path
	var script_dir: String = script_path.get_base_dir()
	return script_dir.path_join("scenes.tres")

func _load_scenes():
	if !ResourceLoader.exists(saved_scenes_resource_path):
		ResourceSaver.save(CSRScenes.new(), saved_scenes_resource_path)
	var scenes_resources: CSRScenes = ResourceLoader.load(saved_scenes_resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	scenes = scenes_resources.scenes

func _rebuild_menu() -> void:
	clear()
	var ii := 0
	for scene in scenes:
		add_item("Run " + scene.name, ii, scene.keyboard_shortcut)
		ii += 1
	add_separator()
	add_item("Select Scenes", SELECT_SCENES_ITEM_ID)

func _on_menu_id_pressed(id: int) -> void:
	if id == SELECT_SCENES_ITEM_ID:
		var select_scenes_popup_instance: ScenesSelector = select_scenes_popup.instantiate()
		select_scenes_popup_instance.saved_scenes_resource_path = saved_scenes_resource_path
		select_scenes_popup_instance.scenes_updated.connect(_on_scenes_updated)
		EditorInterface.get_base_control().add_child(select_scenes_popup_instance)
		select_scenes_popup_instance.popup_centered()
	else:
		if id < scenes.size():
			EditorInterface.play_custom_scene(scenes[id].scene_path)

func _on_scenes_updated() -> void:
	_load_scenes()
	_rebuild_menu()
