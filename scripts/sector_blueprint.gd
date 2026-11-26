class_name SectorBlueprint
extends Control
## Shadow Protocol - SectorBlueprint minimap (Phase 3D-10).
##
## Port of the web HUD's SectorBlueprint (TacticalHud.tsx / TacticalRadar):
## a top-down schematic of the live sector drawn with Control._draw().
## Walls, doors, terminals, extraction, guards and the player are read from
## the running Main3D every frame, so it is a live instrument, not a stub.

const BG := Color(0.05, 0.09, 0.12, 0.72)
const WALL := Color(0.36, 0.46, 0.55, 0.85)
const FLOOR := Color(0.12, 0.20, 0.26, 0.55)
const DOOR := Color(0.98, 0.72, 0.28, 0.95)
const TERMINAL := Color(0.45, 0.95, 1.0, 0.95)
const EXTRACT := Color(0.35, 0.95, 0.55, 0.95)
const PLAYER := Color(0.85, 0.98, 1.0, 1.0)
const GUARD := Color(0.95, 0.45, 0.40, 0.95)
const GUARD_ALERT := Color(1.0, 0.25, 0.20, 1.0)
const GUARD_DOWNED := Color(0.45, 0.45, 0.50, 0.9)

var main: Node = null
var show_guards: bool = true
var cells_drawn: int = 0
var last_draw_ms: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(168, 168)


func bind(scene: Node) -> void:
	main = scene


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t0: int = Time.get_ticks_usec()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), WALL, false, 1.0)
	if main == null:
		last_draw_ms = 0
		return
	var level: Dictionary = main.get("level_data")
	if level.is_empty():
		last_draw_ms = 0
		return
	var grid: Vector2i = level.get("grid_size", Vector2i.ZERO)
	if grid.x <= 0 or grid.y <= 0:
		last_draw_ms = 0
		return
	var pad: float = 8.0
	var cell: float = minf((size.x - pad * 2.0) / float(grid.x),
		(size.y - pad * 2.0) / float(grid.y))
	var origin := Vector2(pad, pad)
	var walls: Dictionary = level.get("wall_cells", {})
	cells_drawn = 0
	for y in range(grid.y):
		for x in range(grid.x):
			var c := Vector2i(x, y)
			var r := Rect2(origin + Vector2(x * cell, y * cell), Vector2(cell, cell))
			if walls.has(c):
				draw_rect(r, WALL)
			else:
				draw_rect(r, FLOOR)
			cells_drawn += 1
	for door in main.get("doors"):
		if is_instance_valid(door) and door.get("cell") != null:
			_dot(origin, cell, door.cell, DOOR, 2.0)
	for term in main.get("terminals"):
		if is_instance_valid(term) and term.get("cell") != null:
			_dot(origin, cell, term.cell, TERMINAL, 2.4)
	var extraction = main.get("extraction")
	if is_instance_valid(extraction) and extraction.get("cell") != null:
		_dot(origin, cell, extraction.cell, EXTRACT, 3.0)
	if show_guards:
		for guard in main.enemies():
			if not is_instance_valid(guard):
				continue
			var gcell: Vector2i = _cell_of(guard.global_position, level)
			var color: Color = GUARD
			if guard.has_method("is_downed") and guard.is_downed():
				color = GUARD_DOWNED
			elif String(guard.get("state")) == "alert":
				color = GUARD_ALERT
			_dot(origin, cell, gcell, color, 2.2)
	var player = main.get("player")
	if is_instance_valid(player):
		_dot(origin, cell, _cell_of(player.global_position, level), PLAYER, 3.2)
	last_draw_ms = (Time.get_ticks_usec() - t0) / 1000


## World -> grid cell, using the live level descriptor (no Main3D helper
## dependency so the blueprint also works against any bound scene).
func _cell_of(world: Vector3, level: Dictionary) -> Vector2i:
	var cs: float = float(level.get("cell_size", 48.0))
	var origin: Vector3 = level.get("origin", Vector3.ZERO)
	return Vector2i(int(floor((world.x - origin.x) / cs)), int(floor((world.z - origin.z) / cs)))


func _dot(origin: Vector2, cell: float, grid_cell: Vector2i, color: Color, r: float) -> void:
	var center := origin + Vector2((grid_cell.x + 0.5) * cell, (grid_cell.y + 0.5) * cell)
	draw_circle(center, maxf(1.5, r), color)
