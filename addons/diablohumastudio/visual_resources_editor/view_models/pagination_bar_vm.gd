@tool
class_name PaginationBarVM
extends RefCounted

signal pagination_updated(page: int, total_pages: int)

var _model: VREModel
var _total_pages: int = 1

func _init(p_model: VREModel) -> void:
	_model = p_model
	_model.pagination_changed.connect(_on_pagination_changed)

func _on_pagination_changed(page: int, total_pages: int) -> void:
	_total_pages = total_pages
	pagination_updated.emit(page, total_pages)

func get_current_page() -> int:
	return _model.session.current_page

func get_total_pages() -> int:
	return _total_pages

func next_page() -> void:
	_model.next_page()

func prev_page() -> void:
	_model.prev_page()
