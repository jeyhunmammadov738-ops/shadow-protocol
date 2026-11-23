class_name LightSource3D
extends Node3D
## Shadow Protocol - 3D dynamic light with gameplay-coupled parameters
## (Phase 3D-3).
##
## Math is IDENTICAL to the 2D LightSource.contribution_at():
## quadratic falloff, zero beyond light_radius, zero when disabled - so the
## stealth model produces the same numbers in 2D and 3D for the same
## relative geometry (proved by tools/test_3d_phase3.gd at 1e-6).
##
## DOCUMENTED APPROXIMATION (same as 2D): no wall occlusion; this is a
## deterministic gameplay lighting model, not a shadow simulation.

@export_range(32.0, 1024.0, 1.0) var light_radius: float = 160.0
@export_range(0.05, 1.0, 0.01) var light_intensity: float = 0.8
## Optional visual lamp; gameplay never depends on it.
var visual: OmniLight3D = null

var enabled: bool = true
var _stealth: Node = null


func _ready() -> void:
	_build_visual()
	_stealth = get_stealth_system()
	if _stealth != null:
		_stealth.register_light(self)


func _exit_tree() -> void:
	if _stealth != null and is_instance_valid(_stealth):
		_stealth.unregister_light(self)


## Resolves the 3D stealth system: explicit override, else the closest
## ancestor exposing register_light (main3d owns one).
func get_stealth_system() -> Node:
	if _stealth != null:
		return _stealth
	var node: Node = get_parent()
	while node != null:
		if node.has_method("register_light") and node.has_method("dynamic_light_at"):
			return node
		node = node.get_parent()
	return null


func _build_visual() -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Visual"
	lamp.omni_range = light_radius
	lamp.light_energy = light_intensity
	lamp.light_color = Color(1.0, 0.88, 0.62)
	lamp.shadow_enabled = false  # mobile budget: gameplay model is authoritative
	add_child(lamp)
	visual = lamp


## Toggles the light for BOTH rendering and gameplay.
func set_light_enabled(active: bool) -> void:
	enabled = active
	if visual != null:
		visual.visible = active


## Deterministic gameplay contribution at [param world_pos].
## Quadratic falloff, zero beyond light_radius, nothing when disabled.
func contribution_at(world_pos: Vector3) -> float:
	if not enabled:
		return 0.0
	var distance: float = world_pos.distance_to(global_position)
	if distance >= light_radius:
		return 0.0
	var t: float = 1.0 - distance / light_radius
	return clampf(light_intensity * t * t, 0.0, 1.0)
