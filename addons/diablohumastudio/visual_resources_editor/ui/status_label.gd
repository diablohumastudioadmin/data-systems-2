@tool
extends Label

var state_manager: VREStateManager = null:
	set(value):
		state_manager = value
		if is_node_ready():
			_connect_state()

var _visible_count: int = 0
var _has_selection: bool = false


func _ready() -> void:
	if state_manager:
		_connect_state()


func _connect_state() -> void:
	state_manager.resources_replaced.connect(_on_resources_replaced)
	state_manager.resources_added.connect(_on_resources_added)
	state_manager.resources_removed.connect(_on_resources_removed)
	state_manager.selection_changed.connect(_on_selection_changed)


func _on_resources_replaced(
		resources: Array[Resource], _props: Array[ResourceProperty]) -> void:
	_visible_count = resources.size()
	var selection_count: int = state_manager.selected_resources.size()
	_has_selection = selection_count > 0
	if _has_selection:
		text = "%d selected" % selection_count
	else:
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
