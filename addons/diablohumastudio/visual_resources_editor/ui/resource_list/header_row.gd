@tool
extends HBoxContainer

const HEADER_FIELD_LABEL_SCENE: PackedScene = preload("uid://ufyx2ezw09xlg")
const FIELD_SEPARATOR_SCENE: PackedScene = preload("uid://y2kj6h91hm8r6")

var current_shared_propery_list: Array[ResourceProperty] = []:
	set(value):
		current_shared_propery_list = value
		if is_inside_tree():
			_rebuild_labels()


func _rebuild_labels() -> void:
	for child: Node in %FieldsContainer.get_children():
		child.queue_free()

	for i: int in current_shared_propery_list.size():
		if i > 0:
			var sep: VSeparator = FIELD_SEPARATOR_SCENE.instantiate()
			%FieldsContainer.add_child(sep)
		var lbl: Label = HEADER_FIELD_LABEL_SCENE.instantiate()
		lbl.text = current_shared_propery_list[i].name
		%FieldsContainer.add_child(lbl)
