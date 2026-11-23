class_name Terminal3D
extends StaticBody3D
## Shadow Protocol - 3D objective terminal (Phase 3D-5).
##
## Procedural primitives only. Lives on the INTERACT layer so the player
## can target it with the interaction ray while it never blocks movement
## (layer 1) or enemy line of sight.

signal completed(terminal_id: StringName)

enum State { AVAILABLE, COMPLETED }

const INTERACT_LAYER: int = 2

var terminal_id: StringName = &"terminal_1"
var state: int = State.AVAILABLE
var _panel: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	_panel = get_node_or_null("Visual/Panel") as MeshInstance3D
	_apply_visual()


func set_terminal_id(id: StringName) -> void:
	terminal_id = id


## Marks the objective complete. Duplicate completion is rejected.
func complete() -> bool:
	if state == State.COMPLETED:
		return false
	state = State.COMPLETED
	_apply_visual()
	completed.emit(terminal_id)
	return true


func is_completed() -> bool:
	return state == State.COMPLETED


## Aim point used by the interaction ray and the distance check.
func interaction_position() -> Vector3:
	return global_position + Vector3(0.0, 70.0, 0.0)


func set_highlight(active: bool) -> void:
	if _panel == null:
		return
	_mat = _panel.get_active_material(0) as StandardMaterial3D
	if _mat == null:
		return
	_mat.emission_energy_multiplier = 2.4 if active else (0.6 if state == State.COMPLETED else 1.2)


func _apply_visual() -> void:
	if _panel == null:
		return
	_mat = _panel.get_active_material(0) as StandardMaterial3D
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_panel.material_override = _mat
	if state == State.COMPLETED:
		_mat.albedo_color = Color(0.32, 0.85, 0.45)
		_mat.emission = Color(0.25, 0.80, 0.40)
		_mat.emission_enabled = true
		_mat.emission_energy_multiplier = 0.6
	else:
		_mat.albedo_color = Color(0.85, 0.66, 0.20)
		_mat.emission = Color(0.95, 0.72, 0.28)
		_mat.emission_enabled = true
		_mat.emission_energy_multiplier = 1.2
