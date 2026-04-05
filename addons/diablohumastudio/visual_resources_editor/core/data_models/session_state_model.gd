@tool
class_name SessionStateModel
extends RefCounted

signal selected_class_changed(class_name_: String)
signal include_subclasses_changed(include: bool)
signal search_filter_changed(filter: String)
signal current_page_changed(page: int)
signal selected_resources_changed(resources: Array[Resource])

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

var selected_resources: Array[Resource] = []:
	set(value):
		if selected_resources != value:
			selected_resources = value
			selected_resources_changed.emit(value)
