@tool
extends EditorPlugin

## Parent plugin for DiabloHumaStudio framework
## Adds toolbar menu and loads child plugins

var _diablo_huma_toolbar_menu: PopupMenu

var inner_plugin_folder_paths: Array[String] = [
	"res://addons/diablohumastudio/data_manager/"
]

func _enter_tree() -> void:
	print("[DiabloHumaStudio] Initializing framework...")

	_add_diablo_huma_toolbar_menu()

	_load_child_plugins()

	print("[DiabloHumaStudio] Framework initialized")


func _exit_tree() -> void:
	remove_tool_menu_item("DiabloHumaStudio")

	print("[DiabloHumaStudio] Framework shut down")

func _add_diablo_huma_toolbar_menu() -> void:
	_diablo_huma_toolbar_menu = PopupMenu.new()
	_diablo_huma_toolbar_menu.name = "DiabloHumaStudioMenu"
	add_tool_submenu_item("DiabloHumaStudio", _diablo_huma_toolbar_menu)

func _load_child_plugins() -> void:
	for inner_plugin_folder_path in inner_plugin_folder_paths:
		if !EditorInterface.is_plugin_enabled(inner_plugin_folder_path):
			EditorInterface.set_plugin_enabled(inner_plugin_folder_path, true)
			print("[DiabloHumaStudio] Loaded Data Manager plugin")
		else:
			push_error("[DiabloHumaStudio] Failed to load Data Manager plugin")
