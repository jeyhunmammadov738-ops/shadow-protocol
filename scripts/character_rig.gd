class_name CharacterRig
extends Node3D
## Shadow Protocol - procedural tactical character rigs (Phase 3D-8).
##
## Zero external assets: every part is a Godot primitive. The rig is a
## small hierarchy so the stride can be animated by rotating limb pivots
## instead of morphing one capsule.
##
## Player: slim operator, tactical vest, shoulder pads, tri-focal visor.
## Guard: bulkier armour, helmet, wide visor, shoulder pads, weapon.

const SKIN := Color(0.62, 0.55, 0.48)
const BOOT := Color(0.10, 0.12, 0.16)

var kind: String = "player"
var parts: Array[MeshInstance3D] = []
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var torso: Node3D = null
var head: Node3D = null
var visor_material: StandardMaterial3D = null
var _stride: float = 0.0
var _state_color: Color = Color.WHITE


static func build_player(parent: Node3D) -> CharacterRig:
	return _build(parent, "player")


static func build_guard(parent: Node3D) -> CharacterRig:
	return _build(parent, "guard")


static func _build(parent: Node3D, which: String) -> CharacterRig:
	var rig := CharacterRig.new()
	rig.name = "Rig"
	rig.kind = which
	parent.add_child(rig)
	rig._assemble()
	return rig


func _assemble() -> void:
	var bulk: float = 1.18 if kind == "guard" else 1.0
	var main_color: Color = Palette.ENEMY_SLATE if kind == "guard" else Palette.PLAYER
	_state_color = main_color
	# --- legs (pivots at the hip so the stride reads as walking) ---
	for side in [-1.0, 1.0]:
		var hip := _pivot(Vector3(7.0 * side * bulk, 34.0, 0.0))
		_box(hip, Vector3(9.0, 30.0, 10.0) * bulk, Vector3(0.0, -15.0, 0.0), main_color.darkened(0.35))
		_box(hip, Vector3(10.0, 7.0, 13.0) * bulk, Vector3(0.0, -31.0, 1.5), BOOT)
		legs.append(hip)
	# --- torso + vest ---
	torso = _pivot(Vector3(0.0, 34.0, 0.0))
	_box(torso, Vector3(24.0, 28.0, 15.0) * bulk, Vector3(0.0, 14.0, 0.0), main_color)
	_box(torso, Vector3(26.0, 17.0, 18.0) * bulk, Vector3(0.0, 15.0, 0.0),
		main_color.darkened(0.25) if kind == "guard" else main_color.darkened(0.15))
	# chest light / radio: small emissive accent
	_box(torso, Vector3(4.0, 3.0, 1.5), Vector3(6.0, 20.0, 9.0),
		Palette.INTERACTIVE, true, 0.9)
	# --- shoulders + arms ---
	for side in [-1.0, 1.0]:
		var shoulder := _pivot(Vector3(15.0 * side * bulk, 45.0, 0.0))
		_box(shoulder, Vector3(9.0, 8.0, 12.0) * bulk, Vector3(3.0 * side, 0.0, 0.0), main_color.darkened(0.2))
		_box(shoulder, Vector3(7.0, 22.0, 8.0) * bulk, Vector3(3.0 * side, -13.0, 0.0), main_color.darkened(0.3))
		_box(shoulder, Vector3(6.0, 6.0, 7.0), Vector3(3.0 * side, -26.0, 0.0), SKIN)
		arms.append(shoulder)
	# --- head ---
	head = _pivot(Vector3(0.0, 52.0, 0.0))
	_box(head, Vector3(13.0, 13.0, 13.0) * bulk, Vector3(0.0, 3.0, 0.0), SKIN.darkened(0.15))
	if kind == "guard":
		_box(head, Vector3(15.0, 9.0, 15.0) * bulk, Vector3(0.0, 9.0, 0.0), main_color.darkened(0.45))
		_box(head, Vector3(13.0, 4.0, 2.0), Vector3(0.0, 4.0, 7.0), Palette.INTERACTIVE, true, 1.8)
		# weapon silhouette across the chest
		_box(torso, Vector3(4.0, 4.0, 26.0), Vector3(11.0, 12.0, 10.0), BOOT)
		_box(torso, Vector3(2.0, 2.0, 3.0), Vector3(11.0, 12.0, 24.0), Palette.INTERACTIVE, true, 1.2)
	else:
		# Splinter Cell style tri-focal visor: three glowing lenses
		for i in range(3):
			_box(head, Vector3(3.0, 2.2, 1.2), Vector3(-4.0 + 4.0 * i, 5.0, 6.6),
				Palette.PLAYER_SPRINT, true, 2.2)
		# backpack + thigh holster for silhouette
		_box(torso, Vector3(16.0, 16.0, 6.0), Vector3(0.0, 16.0, -9.0), BOOT)
		_box(legs[1], Vector3(4.0, 12.0, 4.0), Vector3(7.0, -18.0, 2.0), BOOT)


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, offset: Vector3, color: Color,
		emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	parent.add_child(mi)
	parts.append(mi)
	if emissive:
		visor_material = mat
	return mi


## Stride/limb animation. [param speed] is horizontal speed in units/s.
func animate(delta: float, speed: float, crouching: bool, sprinting: bool) -> void:
	var moving: float = clampf(speed / 220.0, 0.0, 1.6)
	if moving > 0.05:
		_stride += delta * (10.0 if sprinting else 7.0) * maxf(0.35, moving)
	var swing: float = sin(_stride) * (0.55 + 0.25 * moving) * clampf(moving * 2.0, 0.0, 1.0)
	if legs.size() == 2:
		legs[0].rotation.x = swing
		legs[1].rotation.x = -swing
	if arms.size() == 2:
		arms[0].rotation.x = -swing * 0.7
		arms[1].rotation.x = swing * 0.7
	if torso != null:
		torso.position.y = 34.0 + absf(sin(_stride * 2.0)) * 1.2 * moving
		torso.rotation.z = sin(_stride) * 0.03 * moving
	if crouching:
		if legs.size() == 2:
			legs[0].rotation.x = 0.9
			legs[1].rotation.x = -0.5
		if torso != null:
			torso.rotation.x = 0.22


## Guard alert tinting keeps the FSM readable on the new rig.
func set_state_color(color: Color) -> void:
	if color == _state_color:
		return
	_state_color = color
	for mi in parts:
		if mi.material_override is StandardMaterial3D:
			var mat := mi.material_override as StandardMaterial3D
			if not mat.emission_enabled:
				mat.albedo_color = color.darkened(0.2)


# ------------------------------------------------------------ melee (3D-11) --
## Animation-driven melee: a windup, an impact frame, then a recovery. Damage
## is registered at the impact frame by the caller, not on the input frame.
const MELEE_WINDUP: float = 0.18
const MELEE_RECOVERY: float = 0.24

var melee_timer: float = -1.0
var melee_impact_done: bool = false


func start_melee() -> void:
	melee_timer = 0.0
	melee_impact_done = false


func melee_active() -> bool:
	return melee_timer >= 0.0


## True exactly once, on the frame the blade reaches the impact point.
func melee_impact_frame() -> bool:
	if melee_timer < 0.0 or melee_impact_done:
		return false
	if melee_timer >= MELEE_WINDUP:
		melee_impact_done = true
		return true
	return false


func tick_melee(delta: float) -> void:
	if melee_timer < 0.0:
		return
	melee_timer += delta
	if melee_timer > MELEE_WINDUP + MELEE_RECOVERY:
		melee_timer = -1.0
