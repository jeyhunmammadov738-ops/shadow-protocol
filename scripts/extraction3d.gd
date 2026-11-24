class_name Extraction3D
extends Node3D
## Shadow Protocol - 3D extraction beacon (Phase 3D-5).
## Purely visual state mirror of the real mission state; no gameplay
## authority (MissionManager decides success).

enum VisState { LOCKED, ACTIVE, DONE }

var vis_state: int = VisState.LOCKED
var _beam: MeshInstance3D
var _mat: StandardMaterial3D
var _pulse: float = 0.0


func _ready() -> void:
	_beam = get_node_or_null("Visual/Beam") as MeshInstance3D
	_apply()


func set_active(active: bool) -> void:
	if vis_state == VisState.DONE:
		return
	vis_state = VisState.ACTIVE if active else VisState.LOCKED
	_apply()


func set_completed() -> void:
	vis_state = VisState.DONE
	_apply()


func is_active() -> bool:
	return vis_state == VisState.ACTIVE


func _process(delta: float) -> void:
	if vis_state != VisState.ACTIVE or _mat == null:
		return
	_pulse += delta
	_mat.emission_energy_multiplier = 1.2 + 0.8 * absf(sin(_pulse * 2.2))


func _apply() -> void:
	if _beam == null:
		return
	_mat = _beam.get_active_material(0) as StandardMaterial3D
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_beam.material_override = _mat
	_mat.emission_enabled = true
	match vis_state:
		VisState.LOCKED:
			_mat.albedo_color = Palette.EXTRACTION_LOCKED
			_mat.emission = Palette.EXTRACTION_LOCKED.darkened(0.3)
			_mat.emission_energy_multiplier = 0.25
		VisState.ACTIVE:
			_mat.albedo_color = Palette.EXTRACTION
			_mat.emission = Palette.EXTRACTION
			_mat.emission_energy_multiplier = 1.2
		VisState.DONE:
			_mat.albedo_color = Palette.PLAYER_SPRINT
			_mat.emission = Palette.PLAYER_SPRINT
			_mat.emission_energy_multiplier = 2.0
