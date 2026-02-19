@tool
extends DiabloHumaStudioPlugin

## DataManager Sub-Plugin
## Provides CRUD interface for game data types and instances.
## Registers DatabaseManager as autoload "DBManager" for runtime game code access.

const TOOLBAR_MENU_NAME: String = "DataManager"
const DATABASE_MANAGER_SCRIPT := \
	"res://addons/diablohumastudio/database_manager/core/database_manager.gd"

func _enter_tree() -> void:
	add_autoload_singleton("DBManager", DATABASE_MANAGER_SCRIPT)
	add_toolbar_menu()

func add_toolbar_menu():
	var tool_bar_menu := DataManagerToolbar.new()
	MainToolbarPlugin.add_toolbar_shubmenu(TOOLBAR_MENU_NAME, tool_bar_menu, self)

func _exit_tree() -> void:
	MainToolbarPlugin.remove_toolbar_submenu(TOOLBAR_MENU_NAME, self)
	remove_autoload_singleton("DBManager")
