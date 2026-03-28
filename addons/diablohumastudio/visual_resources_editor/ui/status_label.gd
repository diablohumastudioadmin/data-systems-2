@tool
extends Label

var _visible_count: int = 0
var _has_selection: bool = false


func initialize(state: VREStateManager) -> void:
	state.resources_replaced.connect(_on_resources_replaced)
	state.resources_added.connect(_on_resources_added)
	state.resources_removed.connect(_on_resources_removed)
	state.selection_changed.connect(_on_selection_changed)


func _on_resources_replaced(
			resources: Array[Resource], _props: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	text = "%d resource(s)" % _visible_count


func _on_resources_added(resources: Array[Resource]) -> void:
	_visible_count += resources.size()
	if not _has_selection:
		text = "%d resource(s)" % _visible_count


func _on_resources_removed(resources: Array[Resource]) -> void:
	_visible_count -= resources.size()
	if not _has_selection:
		text = "%d resource(s)" % _visible_count


func _on_selection_changed(resources: Array[Resource]) -> void:
	var count: int = resources.size()
	_has_selection = count > 0
	if _has_selection:
		text = "%d selected" % count
	else:
		text = "%d resource(s)" % _visible_count
