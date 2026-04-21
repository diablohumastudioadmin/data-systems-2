@tool
extends Label

var vm: DH_VRE_ResourceListVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	vm.status_text_changed.connect(_on_counts_updated)
	_on_counts_updated(vm.get_visible_count(), vm.get_selected_count())


func _on_counts_updated(visible_count: int, selected_count: int) -> void:
	if selected_count > 0:
		text = "%d selected" % selected_count
	else:
		text = "%d resource(s)" % visible_count
