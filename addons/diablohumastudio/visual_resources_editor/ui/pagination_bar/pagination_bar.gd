@tool
extends HBoxContainer

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	%PrevBtn.pressed.connect(state_manager.prev_page)
	%NextBtn.pressed.connect(state_manager.next_page)
	state_manager.pagination_changed.connect(_on_pagination_changed)


func _on_pagination_changed(page: int, page_count: int) -> void:
	visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1
