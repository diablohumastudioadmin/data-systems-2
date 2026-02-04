class_name RunSceneData 
extends Resource

@export var name: String
@export var keyboard_shortcut: Key
@export_file var scene_path: String = "res://screens/"

func _init(name_: String = "", keyboard_shortcut_: Key = KEY_NONE, scene_path_: String = "") -> void:
	name = name_
	keyboard_shortcut = keyboard_shortcut_
	scene_path = scene_path_
