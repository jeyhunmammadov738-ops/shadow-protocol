class_name PropFactory
extends Node3D
## Shadow Protocol - procedural props for the 3D-9 entity set.
##
## Zero external assets: every prop is built from Godot primitives with
## the Neon Noir palette, one material per prop kind so the draw budget
## stays flat.

const ACCENT := Color(0.98, 0.72, 0.28)
const METAL := Color(0.24, 0.28, 0.34)
const DARK := Color(0.10, 0.12, 0.16)


static func make_security_camera() -> Node3D:
	var root := Node3D.new()
	root.name = "SecurityCamera"
	_box(root, Vector3(12, 6, 18), Vector3.ZERO, METAL)
	_box(root, Vector3(6, 6, 6), Vector3(0, 0, 11), DARK)
	_box(root, Vector3(4, 3, 1.5), Vector3(0, 0, 14.6), ACCENT, true, 2.0)
	_box(root, Vector3(3, 12, 3), Vector3(0, 9, -4), DARK)
	return root


static func make_laser_emitter() -> Node3D:
	var root := Node3D.new()
	root.name = "LaserEmitter"
	_box(root, Vector3(8, 10, 8), Vector3.ZERO, METAL)
	_box(root, Vector3(4, 4, 1.2), Vector3(0, 0, 4.2), Color(0.95, 0.28, 0.30), true, 2.4)
	return root


static func make_hide_container(kind: String = "crate") -> Node3D:
	var root := Node3D.new()
	root.name = "HideContainer"
	if kind == "locker":
		_box(root, Vector3(34, 74, 22), Vector3(0, 37, 0), METAL.darkened(0.25))
		_box(root, Vector3(30, 3, 1.5), Vector3(0, 56, 11.6), ACCENT.darkened(0.3), true, 0.7)
	else:
		_box(root, Vector3(40, 40, 40), Vector3(0, 20, 0), METAL.darkened(0.15))
		_box(root, Vector3(42, 4, 6), Vector3(0, 38, 0), DARK)
	return root


static func make_breaker_box() -> Node3D:
	var root := Node3D.new()
	root.name = "BreakerBox"
	_box(root, Vector3(26, 34, 12), Vector3.ZERO, METAL)
	_box(root, Vector3(10, 3, 1.2), Vector3(0, 8, 6.6), Color(0.32, 0.85, 0.45), true, 1.6)
	_box(root, Vector3(6, 10, 2), Vector3(-6, -6, 6.4), DARK)
	return root


static func make_decoy() -> Node3D:
	var root := Node3D.new()
	root.name = "Decoy"
	_box(root, Vector3(10, 6, 10), Vector3.ZERO, DARK)
	_box(root, Vector3(3, 4, 3), Vector3(0, 5, 0), ACCENT, true, 1.4)
	return root


static func make_vent_hatch() -> Node3D:
	var root := Node3D.new()
	root.name = "VentHatch"
	_box(root, Vector3(34, 30, 4), Vector3.ZERO, METAL.darkened(0.35))
	for i in range(4):
		_box(root, Vector3(28, 2, 1.2), Vector3(0, -9 + i * 6, 2.6), DARK)
	return root


static func make_barricade(width: float = 72.0, height: float = 46.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Barricade"
	_box(root, Vector3(width, height, 16), Vector3(0, height * 0.5, 0), METAL.darkened(0.2))
	_box(root, Vector3(width + 4, 4, 20), Vector3(0, height, 0), ACCENT.darkened(0.45), true, 0.5)
	return root


static func make_dropped_weapon() -> Node3D:
	var root := Node3D.new()
	root.name = "DroppedWeapon"
	_box(root, Vector3(26, 4, 6), Vector3.ZERO, DARK)
	_box(root, Vector3(8, 6, 8), Vector3(-8, -2, 0), METAL)
	return root


static func _box(parent: Node3D, size: Vector3, offset: Vector3, color: Color,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	return mi
