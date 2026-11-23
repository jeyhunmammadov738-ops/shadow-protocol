class_name NoiseEvent3D
extends RefCounted
## Shadow Protocol - 3D counterpart of NoiseEvent (Phase 3D-3).
##
## Same contract as the 2D event (scripts/noise_event.gd), carrying a
## Vector3 origin so 3D enemies can consume it. The 2D event is untouched.

## World position where the sound originated (x, y, z).
var position: Vector3 = Vector3.ZERO
## Effective hearing radius in world units.
var radius: float = 0.0
## Identifier of the emitting source ("player", future: "camera", ...).
var source_id: StringName = &""
## Movement state that generated the noise: "crouch", "walk", "sprint", "still".
var movement_state: StringName = &""
## Engine frame at emission time (deduplication and ordering aid).
var frame: int = -1
## Optional extra metadata for future consumers (never required).
var extra: Dictionary = {}


func setup(p_position: Vector3, p_radius: float, p_source_id: StringName,
		p_movement_state: StringName, p_frame: int) -> void:
	position = p_position
	radius = p_radius
	source_id = p_source_id
	movement_state = p_movement_state
	frame = p_frame


func to_string_repr() -> String:
	return "NoiseEvent3D(pos=%s radius=%.0f source=%s state=%s frame=%d)" % [
		position, radius, source_id, movement_state, frame]
