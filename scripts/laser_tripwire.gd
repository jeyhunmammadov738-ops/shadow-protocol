class_name LaserTripwire3D
extends Node3D
## Shadow Protocol - cycling laser tripwire (Phase 3D-9).
##
## Port of LaserTripwireDef (types.ts): endpoints, on/off cycle durations
## and a phase offset, plus EMP disabling. Tripping raises the alarm
## through the same signal the mission layer already understands.

signal tripped()
signal disabled_changed(disabled: bool)

var tripwire_id: StringName = &"laser_1"
var point_a: Vector3 = Vector3.ZERO
var point_b: Vector3 = Vector3.ZERO
var cycle_on: float = 2.4
var cycle_off: float = 1.6
var phase_offset: float = 0.0
var disabled: bool = false
var active: bool = true
var trip_count: int = 0

var _time: float = 0.0
var _was_touching: bool = false


func configure(a: Vector3, b: Vector3, on_time: float, off_time: float, phase: float) -> void:
	point_a = a
	point_b = b
	cycle_on = on_time
	cycle_off = off_time
	phase_offset = phase


func set_disabled(value: bool) -> void:
	if disabled == value:
		return
	disabled = value
	active = false if value else active
	disabled_changed.emit(disabled)


func cycle_length() -> float:
	return maxf(0.01, cycle_on + cycle_off)


## Deterministic on/off state for a given time (same rule as the web build:
## phase offset shifts the whole cycle).
func is_on_at(time: float) -> bool:
	if disabled:
		return false
	var t: float = fposmod(time + phase_offset, cycle_length())
	return t < cycle_on


func tick(delta: float, player_pos: Vector3) -> bool:
	_time += delta
	active = is_on_at(_time)
	if not active:
		_was_touching = false
		return false
	var touching: bool = _within_beam(player_pos)
	if touching and not _was_touching:
		trip_count += 1
		tripped.emit()
	_was_touching = touching
	return touching


## Distance from the player to the beam segment, with a small body radius.
func _within_beam(pos: Vector3, radius: float = 16.0) -> bool:
	var ab: Vector3 = point_b - point_a
	var ab_len_sq: float = ab.length_squared()
	if ab_len_sq < 0.0001:
		return pos.distance_to(point_a) <= radius
	var t: float = clampf((pos - point_a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector3 = point_a + ab * t
	# Horizontal distance only: the beam crosses at torso height.
	return Vector2(pos.x - closest.x, pos.z - closest.z).length() <= radius
