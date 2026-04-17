@tool
class_name ResourceSorter

## Sorts `resources` in place by `column`. `column` empty sorts by filename.
## `props` is the shared property list used to look up the column type.
static func sort(
	resources: Array[Resource],
	column: String,
	ascending: bool,
	props: Array[ResourceProperty]
) -> void:
	if resources.size() < 2:
		return

	var prop_type: int = TYPE_NIL
	if not column.is_empty():
		for p: ResourceProperty in props:
			if p.name == column:
				prop_type = p.type
				break

	resources.sort_custom(func(a: Resource, b: Resource) -> bool:
		var val_a: Variant = _sort_value(a, column, prop_type)
		var val_b: Variant = _sort_value(b, column, prop_type)

		# null sorts last regardless of direction
		if val_a == null and val_b == null:
			return a.resource_path < b.resource_path
		if val_a == null:
			return false
		if val_b == null:
			return true

		var cmp: int = _compare_values(val_a, val_b, prop_type)
		if cmp == 0:
			return a.resource_path < b.resource_path
		return cmp < 0 if ascending else cmp > 0
	)


static func _sort_value(res: Resource, column: String, prop_type: int) -> Variant:
	if column.is_empty():
		return res.resource_path.get_file()
	var val: Variant = res.get(column) if column in res else null
	return val


static func _compare_values(a: Variant, b: Variant, prop_type: int) -> int:
	match prop_type:
		TYPE_STRING, TYPE_STRING_NAME:
			return str(a).naturalnocasecmp_to(str(b))
		TYPE_INT, TYPE_FLOAT:
			var fa: float = float(a)
			var fb: float = float(b)
			if fa < fb: return -1
			if fa > fb: return 1
			return 0
		TYPE_BOOL:
			var ia: int = 1 if a else 0
			var ib: int = 1 if b else 0
			if ia < ib: return -1
			if ia > ib: return 1
			return 0
		TYPE_VECTOR2:
			var la: float = a.length()
			var lb: float = b.length()
			if la < lb: return -1
			if la > lb: return 1
			return 0
		TYPE_VECTOR3:
			var la: float = a.length()
			var lb: float = b.length()
			if la < lb: return -1
			if la > lb: return 1
			return 0
		TYPE_COLOR:
			if a.h != b.h:
				return -1 if a.h < b.h else 1
			if a.v != b.v:
				return -1 if a.v < b.v else 1
			return 0
		TYPE_OBJECT:
			var pa: String = a.resource_path.get_file() if a is Resource and a.resource_path else ""
			var pb: String = b.resource_path.get_file() if b is Resource and b.resource_path else ""
			return pa.naturalnocasecmp_to(pb)
		TYPE_NIL:
			# File-name column (column == "")
			return str(a).naturalnocasecmp_to(str(b))
		_:
			return str(a).naturalnocasecmp_to(str(b))
