class_name FacilityCatalog
extends RefCounted
## Shadow Protocol - deterministic facility entity layout (Phase 3D-9).
##
## Ports the web build's facility entity set (types.ts / levelCatalog.ts:
## SecurityCameraDef, LaserTripwireDef, HideContainerDef, BreakerDef,
## VentHatchDef, BarricadeDef, SecurityJunctionDef) as a PURE derivation
## from the existing layout descriptor.
##
## Deriving instead of extending the tile encoding keeps every existing
## layout byte-identical and leaves BFS reachability validation untouched:
## nothing here adds walls, doors or blocking cells.

const MAX_CAMERAS: int = 4
const MAX_TRIPWIRES: int = 4
const MAX_CONTAINERS: int = 6


static func build(level_data: Dictionary) -> Dictionary:
	var walls: Dictionary = level_data.get("wall_cells", {})
	var walkable: Array = _walkable(level_data)
	walkable.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y)
	var size: float = float(level_data.get("cell_size", 48.0))
	var origin: Vector3 = level_data.get("origin", Vector3.ZERO)

	var cameras: Array = []
	var tripwires: Array = []
	var containers: Array = []
	var breakers: Array = []
	var vents: Array = []
	var decoys: Array = []
	var barricades: Array = []

	# --- cameras: wall-adjacent cells with the longest open sightline ----
	var corner_cells: Array = []
	for cell: Vector2i in walkable:
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if walls.has(cell + d):
				corner_cells.append([cell, d])
				break
	corner_cells.sort_custom(func(a: Array, b: Array) -> bool:
		return _sightline(a[0], walls, size) > _sightline(b[0], walls, size))
	var cam_index: int = 0
	for entry: Array in corner_cells:
		if cam_index >= MAX_CAMERAS:
			break
		if cam_index % 2 == 1 and corner_cells.size() > 2:
			cam_index += 1
			continue
		var cell: Vector2i = entry[0]
		var wall_dir: Vector2i = entry[1]
		cameras.append({
			"id": StringName("cam_%d" % (cam_index + 1)),
			"cell": cell,
			"pos": _center(cell, size, origin),
			# Face away from the wall it is mounted on.
			"base_yaw": atan2(float(-wall_dir.x), float(-wall_dir.y)),
			"sweep_arc": deg_to_rad(70.0),
			"sweep_speed": 0.6 + 0.1 * float(cam_index),
			"range": 5.0 * size,
			"fov": deg_to_rad(52.0),
		})
		cam_index += 1

	# --- tripwires: corridors at least 3 cells long, crossed by the beam --
	var corridors: Array = []
	for cell: Vector2i in walkable:
		var open_x: bool = not walls.has(cell + Vector2i(-1, 0)) \
			and not walls.has(cell + Vector2i(1, 0))
		var open_z: bool = not walls.has(cell + Vector2i(0, -1)) \
			and not walls.has(cell + Vector2i(0, 1))
		if open_x != open_z:
			corridors.append([cell, open_x])
	var ti: int = 0
	for entry: Array in corridors:
		if ti >= MAX_TRIPWIRES:
			break
		if ti % 3 != 0:
			ti += 1
			continue
		var cell: Vector2i = entry[0]
		var along_x: bool = entry[1]
		var half: float = size * 0.5
		var c: Vector3 = _center(cell, size, origin)
		var a: Vector3 = c + (Vector3(0, 0, -half) if along_x else Vector3(-half, 0, 0))
		var b: Vector3 = c + (Vector3(0, 0, half) if along_x else Vector3(half, 0, 0))
		tripwires.append({
			"id": StringName("laser_%d" % (ti + 1)),
			"a": a, "b": b,
			"cycle_on": 2.4, "cycle_off": 1.6,
			"phase_offset": 0.7 * float(ti),
		})
		ti += 1

	# --- hide containers in dead ends, vents on the same cells -----------
	var dead_ends: Array = []
	for cell: Vector2i in walkable:
		var open: int = 0
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if not walls.has(cell + d):
				open += 1
		if open <= 1:
			dead_ends.append(cell)
	var ci: int = 0
	for cell: Vector2i in dead_ends:
		if ci >= MAX_CONTAINERS:
			break
		containers.append({
			"id": StringName("hide_%d" % (ci + 1)),
			"cell": cell,
			"pos": _center(cell, size, origin),
			"kind": "locker" if ci % 2 == 1 else "crate",
		})
		if ci == 0 and dead_ends.size() > 2:
			vents.append({
				"id": StringName("vent_1"), "cell": cell,
				"pos": _center(cell, size, origin),
			})
		ci += 1

	# --- breakers on wall faces, decoys and barricades on open cells -----
	for cell: Vector2i in walkable:
		if breakers.size() >= 2:
			break
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if walls.has(cell + d):
				breakers.append({
					"id": StringName("breaker_%d" % (breakers.size() + 1)),
					"label": "LIGHT BREAKER",
					"cell": cell,
					"pos": _center(cell, size, origin),
					"normal": Vector2(float(d.x), float(d.y)),
					"linked_camera_id": StringName("cam_%d" % (breakers.size() + 1)),
				})
				break
	var mid: int = walkable.size() / 2
	if walkable.size() > 3:
		decoys.append({
			"id": &"decoy_1", "cell": walkable[1],
			"pos": _center(walkable[1], size, origin),
		})
		barricades.append({
			"id": &"barricade_1", "cell": walkable[mid],
			"pos": _center(walkable[mid], size, origin),
			"width": size * 1.5, "height": 46.0,
		})

	return {
		"cameras": cameras,
		"tripwires": tripwires,
		"containers": containers,
		"breakers": breakers,
		"vents": vents,
		"decoys": decoys,
		"barricades": barricades,
	}


static func _walkable(level_data: Dictionary) -> Array:
	var out: Array = []
	var walls: Dictionary = level_data.get("wall_cells", {})
	var grid_size: Vector2i = level_data.get("grid_size", Vector2i.ZERO)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not walls.has(cell):
				out.append(cell)
	return out


static func _center(cell: Vector2i, size: float, origin: Vector3) -> Vector3:
	return origin + Vector3((cell.x + 0.5) * size, 0.0, (cell.y + 0.5) * size)


## Open run from a cell in its longest axis, used to rank camera spots.
static func _sightline(cell: Vector2i, walls: Dictionary, _size: float) -> int:
	var best: int = 0
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var run: int = 0
		for step in range(1, 8):
			if walls.has(cell + d * step):
				break
			run += 1
		best = maxi(best, run)
	return best
