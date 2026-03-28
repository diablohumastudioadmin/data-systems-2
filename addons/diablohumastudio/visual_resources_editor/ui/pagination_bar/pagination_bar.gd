@tool
extends HBoxContainer


func initialize(state: VREStateManager) -> void:
	%PrevBtn.pressed.connect(state.prev_page)
	%NextBtn.pressed.connect(state.next_page)
	state.pagination_changed.connect(_on_pagination_changed)


func _on_pagination_changed(page: int, page_count: int) -> void:
	visible = page_count > 1
	%PageLabel.text = "Page %d / %d" % [page + 1, page_count]
	%PrevBtn.disabled = page == 0
	%NextBtn.disabled = page >= page_count - 1
