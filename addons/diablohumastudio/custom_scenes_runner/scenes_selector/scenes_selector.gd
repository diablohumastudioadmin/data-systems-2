@tool
class_name ScenesSelector
extends Window

signal scenes_updated

var saved_scenes_resource_path: String
var item_scene: PackedScene = preload("uid://70e3ag4jq3k6")
var _scenes: Array[RunnerSceneData]
var _current_item: SceneItem = null

@onready var items_container: VBoxContainer = %ItemsContainer


func _ready() -> void:
	load_scenes()
	_set_items_from_scenes()

func _on_add_button_pressed() -> void:
	_scenes.append(RunnerSceneData.new())
	_set_items_from_scenes()

func _on_save_button_pressed() -> void:
	save_config()
	scenes_updated.emit()
	queue_free()

func _on_close_requested() -> void:
	queue_free()

func save_config() -> void:
	var scenes_resource: RunnerScenes = RunnerScenes.new()
	scenes_resource.scenes = _scenes
	ResourceSaver.save(scenes_resource, saved_scenes_resource_path)

func load_scenes():
	var scenes_resource: RunnerScenes
	if ResourceLoader.exists(saved_scenes_resource_path):
		scenes_resource = ResourceLoader.load(saved_scenes_resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	else:
		scenes_resource = RunnerScenes.new()
	_scenes = scenes_resource.scenes

func _set_items_from_scenes():
	for child in items_container.get_children():
		child.queue_free()
	for scene_data in _scenes:
		var new_item: SceneItem = item_scene.instantiate()
		new_item.set_data(scene_data)
		items_container.add_child(new_item)
