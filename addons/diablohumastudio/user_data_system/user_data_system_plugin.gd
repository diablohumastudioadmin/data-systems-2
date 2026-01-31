@tool
extends EditorPlugin

## UserDataSystem Sub-Plugin
## Minimal plugin - the actual system is an autoload

func _enter_tree() -> void:
	print("[UserDataSystem] Plugin initialized")


func _exit_tree() -> void:
	print("[UserDataSystem] Plugin shut down")
