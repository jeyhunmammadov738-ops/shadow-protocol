class_name StealthSystem3D
extends Node
## Shadow Protocol - 3D stealth/noise core (Phase 3D-3).
##
## Exact 3D counterpart of the 2D StealthSystem autoload. The arithmetic is
## deliberately IDENTICAL: same constants, same order of operations, same
## clamps. Only the coordinate type changes (Vector2 -> Vector3, grid
## (x, y) -> (x, z)). tools/test_3d_phase3.gd proves 2D/3D parity at 1e-6
## for illumination, visibility and noise over a dense input sweep.
##
## The 2D autoload and every 2D script stay untouched: this is a separate
## class owned by main3d.tscn.

signal noise_emitted(event: NoiseEvent3D)

const CELL_SHADOW_VALUE: float = 0.25
const CELL_LIT_VALUE: float = 1.0
const CROUCH_FACTOR: float = 0.55
const MOTION_VISIBILITY_BOOST: float = 0.15

const NOISE_RADIUS_CROUCHED: float = 90.0
const NOISE_RADIUS_WALKING: float = 220.0
const NOISE_RADIUS_SPRINT: float = 320.0

var lit_cells: Dictionary = {}   # Vector2i(grid_x, grid_z) -> true
var cell_size: float = 48.0
var grid_origin: Vector3 = Vector3.ZERO
var wall_cells: Dictionary = {}
var _doors: Array = []
var _lights: Array = []
var _last_noise_frame: Dictionary = {}

# Benchmark counters (same shape as the 2D system).
var bench_enabled: bool = false
var bench_visibility_computes: int = 0
var bench_light_queries: int = 0
var bench_noise_dispatches: int = 0


func bench_reset() -> void:
	bench_visibility_computes = 0
	bench_light_queries = 0
	bench_noise_dispatches = 0


func configure(lit: Dictionary, size: float, origin: Vector3,
		walls: Dictionary = {}) -> void:
	lit_cells = lit
	cell_size = size
	grid_origin = origin
	wall_cells = walls


func register_door(door: Node) -> void:
	if not _doors.has(door):
		_doors.append(door)


func unregister_door(door: Node) -> void:
	_doors.erase(door)


func clear_doors() -> void:
	_doors.clear()


func is_cell_blocked(cell: Vector2i) -> bool:
	if wall_cells.has(cell):
		return true
	for door: Node in _doors:
		if door.has_method("is_open") and not door.is_open():
			if door.has_method("get_cell") and door.get_cell() == cell:
				return true
	return false


func register_light(light: Node) -> void:
	if not _lights.has(light):
		_lights.append(light)


func unregister_light(light: Node) -> void:
	_lights.erase(light)


func light_count() -> int:
	return _lights.size()


## Total contribution of all enabled dynamic lights at a position.
## Additive with a hard clamp at 1.0 (identical to 2D).
func dynamic_light_at(world_pos: Vector3) -> float:
	if bench_enabled:
		bench_light_queries += 1
	var total: float = 0.0
	for light in _lights:
		# Layout reloads free the light nodes before the array is cleared.
		if not is_instance_valid(light):
			continue
		total += light.contribution_at(world_pos)
	return clampf(total, 0.0, 1.0)


## Static grid layer only (0 = shadow 0.25, 1 = lit 1.0).
func grid_illumination_at(world_pos: Vector3) -> float:
	return CELL_LIT_VALUE if lit_cells.has(world_to_grid(world_pos)) else CELL_SHADOW_VALUE


## Combined illumination: max() of the static grid layer and the dynamic
## light layer (same double-counting rule as 2D).
func illumination_at(world_pos: Vector3) -> float:
	return maxf(grid_illumination_at(world_pos), dynamic_light_at(world_pos))


## Normalized visibility 0..1. Motion boost is applied exactly once after
## the illumination and posture factors, then clamped (identical to 2D).
func compute_visibility(world_pos: Vector3, crouching: bool, speed_ratio: float) -> float:
	if bench_enabled:
		bench_visibility_computes += 1
	var value: float = illumination_at(world_pos)
	if crouching:
		value *= CROUCH_FACTOR
	value += MOTION_VISIBILITY_BOOST * clampf(speed_ratio, 0.0, 1.0)
	return clampf(value, 0.0, 1.0)


## Radius of the noise a player in this state generates (identical to 2D).
func noise_radius(crouching: bool, speed_ratio: float, sprinting: bool = false) -> float:
	if crouching:
		return NOISE_RADIUS_CROUCHED
	if sprinting:
		return NOISE_RADIUS_SPRINT
	return NOISE_RADIUS_WALKING * (0.55 + 0.45 * clampf(speed_ratio, 0.0, 1.0))


## Central noise publication point with the same per-frame deduplication
## rule as the 2D system.
func publish_noise(pos: Vector3, radius: float, source_id: StringName,
		movement_state: StringName = &"walk", extra: Dictionary = {}) -> void:
	if bench_enabled:
		bench_noise_dispatches += 1
	var frame: int = Engine.get_process_frames()
	if _last_noise_frame.get(source_id, -1) == frame:
		return
	_last_noise_frame[source_id] = frame
	var event := NoiseEvent3D.new()
	event.setup(pos, radius, source_id, movement_state, frame)
	event.extra = extra
	noise_emitted.emit(event)


# ------------------------------------------------------------ conversion --

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var local_x: float = (world_pos.x - grid_origin.x) / cell_size
	var local_z: float = (world_pos.z - grid_origin.z) / cell_size
	return Vector2i(int(floor(local_x)), int(floor(local_z)))


func grid_to_world(cell: Vector2i) -> Vector3:
	return grid_origin + Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)
