@tool
class_name DH_ScenesAndResourcesResaverToolbar
extends PopupMenu

func _enter_tree() -> void:
	set_meta("dhs_toolbar", true)
	clear()
	add_item("Resave Scenes", 0)
	add_item("Resave Resources", 1)
	add_item("Resave Scenes and Resources", 2)
	id_pressed.connect(_on_menu_id_pressed)

func _on_menu_id_pressed(id: int):
	match id:
		0:
			DH_SRR_ScenesResaver.resave_all_scenes_in_project()
		1:
			DH_SRR_ResourceResaver.resave_all_ressources_in_project()
		3:
			DH_SRR_ScenesResaver.resave_all_scenes_in_project()
			DH_SRR_ResourceResaver.resave_all_ressources_in_project()
