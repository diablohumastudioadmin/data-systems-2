@tool
class_name SessionStateModel
extends RefCounted

signal selected_class_changed(class_name_: String)
signal include_subclasses_changed(include: bool)
signal search_filter_changed(filter: String)
signal current_page_changed(page: int)
signal selected_paths_changed(paths: Array[String])
signal sort_changed(column: String, ascending: bool)

var sort_column: String = ""
var sort_ascending: bool = true

var selected_class: String = "":
	set(value):
		if selected_class != value:
			selected_class = value
			selected_class_changed.emit(value)

var include_subclasses: bool = true:
	set(value):
		if include_subclasses != value:
			include_subclasses = value
			include_subclasses_changed.emit(value)

var search_filter: String = "":
	set(value):
		if search_filter != value:
			search_filter = value
			search_filter_changed.emit(value)

var current_page: int = 0:
	set(value):
		if current_page != value:
			current_page = value
			current_page_changed.emit(value)

var selected_paths: Array[String] = []:
	set(value):
		if selected_paths != value:
			selected_paths = value
			selected_paths_changed.emit(value)


func set_sort(column: String, ascending: bool) -> void:
	if sort_column == column and sort_ascending == ascending:
		return
	sort_column = column
	sort_ascending = ascending
	sort_changed.emit(column, ascending)
