class_name CoverSystem
extends RefCounted
## Shadow Protocol - cover mechanics (Phase 3D-9).
##
## Port of the web build's cover rules (stealthSystem.ts, commit 0bf4408):
## wall-corner cover anchors, waist-high low-cover boxes, and the
## WALL_COVER_FACTOR that reduces visibility when backed against cover.
##
## Deterministic and grid-driven so it matches the 2D/3D parity style of
## the rest of the project: no physics queries, only cell math.

const WALL_COVER_FACTOR: float = 0.62
const LOW_COVER_FACTOR: float = 0.55
const ANCHOR_MIN_DEPTH: int = 1


class CoverAnchor:
	extends RefCounted
	var cell: Vector2i
	var normal: Vector2          # points from the wall into the walkable cell
	var id: StringName
	var kind: StringName = &"wall"

	func _init(c: Vector2i, n: Vector2, name_id: StringName, k: StringName = &"wall") -> void:
		cell = c
		normal = n
		id = name_id
		kind = k


var cell_size: float = 48.0
var grid_origin: Vector3 = Vector3.ZERO
var wall_cells: Dictionary = {}
var low_cover_cells: Dictionary = {}   # Vector2i -> height (world units)
var _anchors: Array[CoverAnchor] = []
var _by_cell: Dictionary = {}          # Vector2i -> Array[CoverAnchor]


func configure(walls: Dictionary, low_cover: Dictionary, size: float, origin: Vector3) -> void:
	wall_cells = walls
	low_cover_cells = low_cover
	cell_size = size
	grid_origin = origin
	_rebuild()


## Every walkable cell that touches a wall gets an anchor whose normal
## points away from that wall. Corner cells therefore get two anchors,
## which is what makes corner peeking readable for the AI.
func _rebuild() -> void:
	_anchors.clear()
	_by_cell.clear()
	var dirs: Array = [
		[Vector2i(0, -1), Vector2(0, 1), &"north"],
		[Vector2i(1, 0), Vector2(-1, 0), &"east"],
		[Vector2i(0, 1), Vector2(0, -1), &"south"],
		[Vector2i(-1, 0), Vector2(1, 0), &"west"],
	]
	for cell: Vector2i in wall_cells.keys():
		for d: Array in dirs:
			var neighbour: Vector2i = cell + (d[0] as Vector2i)
			if wall_cells.has(neighbour):
				continue
			var id := StringName("cover_%d_%d_%s" % [cell.x, cell.y, String(d[2])])
			var anchor := CoverAnchor.new(neighbour, d[1] as Vector2, id, &"wall")
			_anchors.append(anchor)
			if not _by_cell.has(neighbour):
				_by_cell[neighbour] = []
			_by_cell[neighbour].append(anchor)


func anchor_count() -> int:
	return _anchors.size()


func anchors_in(cell: Vector2i) -> Array:
	return _by_cell.get(cell, [])


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((pos.x - grid_origin.x) / cell_size)),
		int(floor((pos.z - grid_origin.z) / cell_size)))


func cell_to_world(cell: Vector2i) -> Vector3:
	return grid_origin + Vector3(
		(cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


## Nearest wall anchor within [param radius_cells] cells, or null.
func nearest_anchor(pos: Vector3, radius_cells: int = 2) -> CoverAnchor:
	var cell: Vector2i = world_to_cell(pos)
	var best: CoverAnchor = null
	var best_dist: float = INF
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := Vector2i(cell.x + dx, cell.y + dy)
			for anchor in anchors_in(c):
				var dist: float = Vector2(pos.x, pos.z).distance_to(
					Vector2(cell_to_world(anchor.cell).x, cell_to_world(anchor.cell).z))
				if dist < best_dist:
					best_dist = dist
					best = anchor
	return best


## True when the actor is backed against cover facing away from it: the
## anchor normal and the threat direction oppose each other.
func is_in_cover(pos: Vector3, threat_pos: Vector3, radius_cells: int = 2) -> bool:
	var anchor: CoverAnchor = nearest_anchor(pos, radius_cells)
	if anchor == null:
		return false
	var to_threat := Vector2(threat_pos.x - pos.x, threat_pos.z - pos.z)
	if to_threat.length_squared() < 0.001:
		return false
	to_threat = to_threat.normalized()
	# Facing the threat while hugging the wall counts as using cover.
	return anchor.normal.dot(to_threat) > 0.35


## Visibility multiplier from cover. 1.0 = exposed, WALL_COVER_FACTOR when
## a wall is used, LOW_COVER_FACTOR when behind a waist-high box.
func cover_factor(pos: Vector3, threat_pos: Vector3, crouching: bool = false) -> float:
	var cell: Vector2i = world_to_cell(pos)
	var factor: float = 1.0
	if low_cover_cells.has(cell):
		var height: float = float(low_cover_cells[cell])
		# Low cover only hides a crouched actor (or one shorter than it).
		if crouching or height >= 40.0:
			factor = minf(factor, LOW_COVER_FACTOR)
	if is_in_cover(pos, threat_pos):
		factor = minf(factor, WALL_COVER_FACTOR)
	return factor


## Cover positions around the actor that break line of sight to the threat,
## nearest first. Used by guard AI to pick a hunker-down spot.
func cover_positions(actor_pos: Vector3, threat_pos: Vector3, radius_cells: int = 3) -> Array[Vector3]:
	var actor_cell: Vector2i = world_to_cell(actor_pos)
	var out: Array[Vector3] = []
	for dy in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var c := Vector2i(actor_cell.x + dx, actor_cell.y + dy)
			if anchors_in(c).is_empty():
				continue
			var world: Vector3 = cell_to_world(c)
			if _line_blocked(world, threat_pos):
				out.append(world)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(actor_pos) < b.distance_squared_to(actor_pos))
	return out


## Grid line walk: true when a wall cell interrupts the segment.
func _line_blocked(from: Vector3, to: Vector3) -> bool:
	var a: Vector2i = world_to_cell(from)
	var b: Vector2i = world_to_cell(to)
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0:
		return false
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var c := Vector2i(
			int(round(lerpf(a.x, b.x, t))),
			int(round(lerpf(a.y, b.y, t))))
		if wall_cells.has(c):
			return true
	return false
