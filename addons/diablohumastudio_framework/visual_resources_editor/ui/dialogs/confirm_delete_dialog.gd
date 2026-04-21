@tool
class_name DH_VRE_ConfirmDeleteDialog
extends ConfirmationDialog

var _pending_paths: Array[String] = []

var vm: DH_VRE_ConfirmDeleteDialogVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.pending_deletions_changed.connect(_on_pending_deletions_changed)


func _on_pending_deletions_changed(paths: Array[String]) -> void:
	_pending_paths = paths
	dialog_text = "Move %d resource(s) to trash?\n\n%s" % [
		paths.size(),
		"\n".join(paths.map(func(p: String) -> String: return p.get_file()))
	]
	popup_centered()


func _on_confirmed() -> void:
	vm.delete(_pending_paths)
	_pending_paths.clear()
