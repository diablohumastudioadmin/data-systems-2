@tool
extends HBoxContainer

var vm: PaginationBarVM = null:
	set(value):
		vm = value
		if is_node_ready():
			_connect_vm()


func _ready() -> void:
	if vm:
		_connect_vm()


func _connect_vm() -> void:
	%PrevBtn.pressed.connect(vm.prev_page)
	%NextBtn.pressed.connect(vm.next_page)
	vm.pagination_updated.connect(_on_pagination_updated)


func _on_pagination_updated(page: int, page_count: int) -> void:
	visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1
