@tool
extends EditorPlugin

## ActionsSystem Sub-Plugin
## Minimal plugin - the actual system is an autoload

func _enter_tree() -> void:
	print("[ActionsSystem] Plugin initialized")


func _exit_tree() -> void:
	print("[ActionsSystem] Plugin shut down")
