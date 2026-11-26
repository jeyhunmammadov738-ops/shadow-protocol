class_name SecurityCamera3D
extends Node3D
## Shadow Protocol - sweeping security camera (Phase 3D-9).
##
## Port of SecurityCameraDef (types.ts): base yaw, sweep arc, sweep speed,
## range and FOV, plus EMP disabling. Detection is grid-based (wall cells
## block the beam) so it matches the deterministic style of the rest of
## the project and never depends on physics timing.

signal spotted_player()
signal disabled_changed(disabled: bool)

var camera_id: StringName = &"cam_1"
var base_yaw: float = 0.0        # radians, direction (sin, cos)
var sweep_arc: float = deg_to_rad(70.0)
var sweep_speed: float = 0.6     # rad/s
var view_range: float = 360.0
var view_fov: float = deg_to_rad(52.0)
var disabled: bool = false
var current_yaw: float = 0.0

var _time: float = 0.0
var _walls: Dictionary = {}
var _cell_size: float = 48.0
var _origin: Vector3 = Vector3.ZERO
var _spotted: bool = false


func configure(walls: Dictionary, cell_size: float, origin: Vector3) -> void:
	_walls = walls
	_cell_size = cell_size
	_origin = origin


## Direction the camera currently faces, on the XZ plane.
func facing() -> Vector3:
	return Vector3(sin(current_yaw), 0.0, cos(current_yaw))


func set_disabled(value: bool) -> void:
	if disabled == value:
		return
	disabled = value
	_spotted = false
	disabled_changed.emit(disabled)


func is_spotting() -> bool:
	return _spotted


func tick(delta: float, player_pos: Vector3) -> bool:
	_time += delta
	if disabled:
		_spotted = false
		return false
	current_yaw = base_yaw + sin(_time * sweep_speed) * sweep_arc * 0.5
	var sees: bool = can_see(player_pos)
	if sees != _spotted:
		_spotted = sees
		if sees:
			spotted_player.emit()
	return sees


func can_see(player_pos: Vector3) -> bool:
	if disabled:
		return false
	var to_player := player_pos - global_position
	if to_player.length() > view_range:
		return false
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length_squared() < 1.0:
		return true
	var angle: float = facing().angle_to(flat.normalized())
	if angle > view_fov * 0.5:
		return false
	return not _segment_blocked(global_position, player_pos)


## Grid walk for wall occlusion; keeps camera detection identical in
## headless tests and on device.
func _segment_blocked(from: Vector3, to: Vector3) -> bool:
	if _walls.is_empty():
		return false
	var a := Vector2i(int(floor((from.x - _origin.x) / _cell_size)),
		int(floor((from.z - _origin.z) / _cell_size)))
	var b := Vector2i(int(floor((to.x - _origin.x) / _cell_size)),
		int(floor((to.z - _origin.z) / _cell_size)))
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps <= 0:
		return false
	for i in range(1, steps):
		var t: float = float(i) / float(steps)
		var c := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
		if _walls.has(c):
			return true
	return false
