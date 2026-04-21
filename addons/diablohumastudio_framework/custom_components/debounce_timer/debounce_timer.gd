@tool
extends Timer
class_name DH_DebounceTimer

var callback: Callable
var args: Array

func _ready() -> void:
	one_shot = true
	if not timeout.is_connected(_on_timout):
		timeout.connect(_on_timout)

func start_debouncing(_callback: Callable, ..._args: Array):
	callback = _callback
	args = _args
	start()

func _on_timout():
	print(callback)
	if callback:
		if args:
			callback.call(args)
		else:
			callback.call()

func _exit_tree() -> void:
	if timeout.is_connected(_on_timout):
		timeout.disconnect(_on_timout)
