@tool
class_name DH_VRE_Toolbar
extends HBoxContainer

var vm: DH_VRE_ToolbarVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.actions_availability_changed.connect(_update_actions)
	_update_actions()


func _update_actions() -> void:
	var count: int = vm.get_selected_count()
	%DeleteSelectedBtn.text = "Delete Selected (%d)" % count if count > 0 else "Delete Selected"
	%DeleteSelectedBtn.disabled = not vm.is_delete_enabled()
	%CreateBtn.disabled = not vm.is_create_enabled()
	%RefreshBtn.disabled = not vm.is_refresh_enabled()


func _on_create_btn_pressed() -> void:
	vm.request_create()


func _on_delete_selected_pressed() -> void:
	vm.request_delete()


func _on_refresh_btn_pressed() -> void:
	vm.request_refresh()
