class_name VisionConeMesh
extends MeshInstance3D
## Shadow Protocol - decorative 3D vision cone (Phase 3D-4).
##
## Procedural triangle fan in the XZ plane at guard eye height. ZERO
## gameplay authority: detection is decided by enemy3d.gd's dot-product +
## raycast model. This mesh exists only so the player can read the guard's
## facing, and it is tinted from the real AI state.

const SEGMENTS: int = 24
const HEIGHT: float = 8.0

var radius: float = 340.0
var fov_degrees: float = 100.0
var _mesh: ArrayMesh = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.45, 0.95, 1.0, 0.12)
	material_override = _material
	rebuild(radius, fov_degrees)


## Rebuilds the fan for a new range/FOV (called once per spawn).
func rebuild(new_radius: float, new_fov_degrees: float) -> void:
	radius = new_radius
	fov_degrees = new_fov_degrees
	var verts: PackedVector3Array = [Vector3(0, HEIGHT, 0)]
	var half: float = deg_to_rad(fov_degrees * 0.5)
	for i in range(SEGMENTS + 1):
		var angle: float = -half + (2.0 * half) * (float(i) / float(SEGMENTS))
		verts.append(Vector3(-sin(angle) * radius, HEIGHT, -cos(angle) * radius))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var idx: PackedInt32Array = []
	for i in range(1, SEGMENTS + 1):
		idx.append(0)
		idx.append(i)
		idx.append(i + 1)
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = _mesh


## State tint from the real FSM (visual only).
func set_tint(color: Color, alpha: float = 0.14) -> void:
	if _material == null:
		return
	_material.albedo_color = Color(color.r, color.g, color.b, alpha)
