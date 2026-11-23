class_name Door3D
extends StaticBody3D
## Shadow Protocol - 3D door (Phase 3D-5).
##
## Closed by default and solid on the WORLD layer (1), so it blocks
## movement AND enemy raycast line of sight exactly like a wall. Opening
## disables the collider and notifies the stealth navigation state, so
## enemy vision and path queries change on the same frame.

signal state_changed(is_open: bool)

const WORLD_LAYER: int = 1

var is_open_flag: bool = false
var cell: Vector2i = Vector2i(-1, -1)
var _panel: Node3D
var _collider: CollisionShape3D
var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = WORLD_LAYER
	collision_mask = 0
	_panel = get_node_or_null("Panel") as Node3D
	_collider = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_apply_state()


## Closed/open query used by StealthSystem3D.is_cell_blocked().
func is_open() -> bool:
	return is_open_flag


func get_cell() -> Vector2i:
	return cell


func set_cell(c: Vector2i) -> void:
	cell = c


func set_state(open: bool) -> void:
	if is_open_flag == open:
		return
	is_open_flag = open
	_apply_state()
	state_changed.emit(is_open_flag)


func toggle() -> void:
	set_state(not is_open_flag)


func interaction_position() -> Vector3:
	return global_position + Vector3(0.0, 60.0, 0.0)


func _apply_state() -> void:
	# Deferred: physics state must not change inside a query/step callback.
	set_deferred("collision_layer", 0 if is_open_flag else WORLD_LAYER)
	if _panel != null:
		_panel.position.y = 130.0 if is_open_flag else 65.0
		if _panel.has_node("Face"):
			var face: MeshInstance3D = _panel.get_node("Face") as MeshInstance3D
			_mat = face.get_active_material(0) as StandardMaterial3D
			if _mat != null:
				_mat.albedo_color = Color(0.35, 0.62, 0.72) if is_open_flag else Color(0.42, 0.46, 0.55)
