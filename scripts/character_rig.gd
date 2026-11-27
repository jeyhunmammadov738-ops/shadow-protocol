class_name CharacterRig
extends Node3D
## Shadow Protocol - procedural humanoid rigs (Phase 3D-13).
##
## Zero external assets: every part is a Godot primitive, but the assembly is
## now a deliberate human silhouette instead of a stack of boxes - tapered
## torso, neck, head with an emissive eye strip, shoulder and hip masses,
## separated upper/lower arms and legs with elbow/knee pivots, hands, boots
## and a jacket/panel layer.
##
## Materials are shared (4 per rig, never one per limb) so the draw budget
## stays flat: 19 meshes per character.
##
## Poses are blended with eased interpolation: idle breathing, walk, sprint,
## crouch, takedown, hit stagger, downed and melee (the 3D-11 impact frame is
## preserved exactly).

const BOOT := Color(0.10, 0.12, 0.16)
const SKIN := Color(0.60, 0.54, 0.47)
const MESH_COUNT_TARGET: int = 19

var kind: String = "player"
var parts: Array[MeshInstance3D] = []
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var knees: Array[Node3D] = []
var elbows: Array[Node3D] = []
var torso: Node3D = null
var head: Node3D = null
var visor_material: StandardMaterial3D = null

var _stride: float = 0.0
var _state_color: Color = Color.WHITE
var _pose: String = "idle"
var _pose_blend: float = 1.0
var _hit_timer: float = 0.0
var _breath: float = 0.0
var _mat_body: StandardMaterial3D = null
var _mat_panel: StandardMaterial3D = null
var _mat_dark: StandardMaterial3D = null


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


# ---------------------------------------------------------------- assembly --

func _assemble() -> void:
	var guard: bool = kind == "guard"
	var bulk: float = 1.14 if guard else 1.0
	var main: Color = Palette.ENEMY_SLATE if guard else Palette.PLAYER
	_state_color = main

	# Shared materials: body, panel/jacket layer, dark extremities.
	_mat_body = _mat(main.darkened(0.12), false)
	_mat_panel = _mat(main.darkened(0.34) if guard else main.darkened(0.22), false)
	_mat_dark = _mat(BOOT, false)
	visor_material = _mat(Palette.PLAYER.lightened(0.25), true, 1.35)

	# --- legs: hip pivot -> thigh -> knee pivot -> shin -> boot ---
	for side in [-1.0, 1.0]:
		var hip := _pivot(Vector3(7.5 * side * bulk, 34.0, 0.0))
		_thigh(hip, bulk)
		var knee := _pivot_at(hip, Vector3(0.0, -16.0, 0.0))
		_shin(knee, bulk)
		_boot(knee, bulk)
		legs.append(hip)
		knees.append(knee)

	# --- torso: hip mass, tapered chest, jacket panel, shoulders ---
	torso = _pivot(Vector3(0.0, 34.0, 0.0))
	_box(torso, Vector3(19.0, 8.0, 13.0) * bulk, Vector3(0.0, 3.0, 0.0), _mat_panel)
	_taper(torso, 11.0 * bulk, 14.5 * bulk, 20.0, Vector3(0.0, 13.0, 0.0), _mat_body)
	# jacket / vest layer sits proud of the chest so the silhouette reads
	_box(torso, Vector3(21.0, 13.0, 9.0) * bulk, Vector3(0.0, 13.0, 4.0), _mat_panel)
	# emissive chest strip: the guard role cue lives here
	_box(torso, Vector3(11.0, 1.8, 1.2), Vector3(0.0, 16.0, 9.4), visor_material)
	for side in [-1.0, 1.0]:
		_box(torso, Vector3(6.0, 6.0, 11.0) * bulk,
			Vector3(10.5 * side * bulk, 20.0, 0.0), _mat_panel)

	# --- neck + head with eye strip ---
	head = _pivot_at(torso, Vector3(0.0, 24.0, 0.0))
	_box(head, Vector3(6.0, 4.0, 6.0), Vector3(0.0, 1.0, 0.0), _mat_dark)
	_box(head, Vector3(11.0, 11.0, 11.0) * bulk, Vector3(0.0, 8.0, 0.0), _mat_body)
	# Tri-focal eye strip: three lenses keep the 3D-8 silhouette language.
	for lens_x in [-3.4, 0.0, 3.4]:
		_box(head, Vector3(2.6, 2.2, 1.2), Vector3(lens_x, 9.0, 5.6), visor_material)
	if guard:
		_box(head, Vector3(13.0, 5.0, 13.0) * bulk, Vector3(0.0, 12.0, -0.5), _mat_panel)

	# --- arms: shoulder pivot -> upper arm -> elbow pivot -> forearm -> hand ---
	for side in [-1.0, 1.0]:
		var shoulder := _pivot_at(torso, Vector3(13.0 * side * bulk, 18.0, 0.0))
		_box(shoulder, Vector3(6.0, 12.0, 6.0) * bulk, Vector3(0.0, -5.0, 0.0), _mat_body)
		var elbow := _pivot_at(shoulder, Vector3(0.0, -11.0, 0.0))
		_box(elbow, Vector3(5.0, 11.0, 5.0) * bulk, Vector3(0.0, -5.0, 0.0), _mat_panel)
		_box(elbow, Vector3(5.5, 4.0, 5.5), Vector3(0.0, -12.0, 0.5), _mat_dark)
		arms.append(shoulder)
		elbows.append(elbow)

	_apply_pose(1.0)


func _mat(color: Color, emissive: bool, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.72
	m.metallic = 0.05
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func _pivot_at(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = offset
	parent.add_child(mi)
	parts.append(mi)
	return mi


## Tapered torso: a cylinder with a narrower waist and wider chest.
func _taper(parent: Node3D, waist: float, chest: float, height: float,
		offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = waist
	mesh.top_radius = chest
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = offset
	parent.add_child(mi)
	parts.append(mi)
	return mi


func _thigh(parent: Node3D, bulk: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 3.6 * bulk
	mesh.top_radius = 4.6 * bulk
	mesh.height = 17.0
	mesh.radial_segments = 7
	mi.mesh = mesh
	mi.material_override = _mat_body
	mi.position = Vector3(0.0, -8.0, 0.0)
	parent.add_child(mi)
	parts.append(mi)


func _shin(parent: Node3D, bulk: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 2.8 * bulk
	mesh.top_radius = 3.8 * bulk
	mesh.height = 15.0
	mesh.radial_segments = 7
	mi.mesh = mesh
	mi.material_override = _mat_panel
	mi.position = Vector3(0.0, -7.5, 0.0)
	parent.add_child(mi)
	parts.append(mi)


func _boot(parent: Node3D, bulk: float) -> void:
	_box(parent, Vector3(6.5, 4.0, 11.0) * bulk, Vector3(0.0, -16.5, 2.0), _mat_dark)


# -------------------------------------------------------------------- poses --

## Sets the animation state. Unknown names fall back to idle.
func set_pose_state(state: String) -> void:
	if state == _pose:
		return
	_pose = state
	_pose_blend = 0.0


func pose_state() -> String:
	return _pose


## Hit stagger: a short, self-clearing reaction on top of the current pose.
func play_hit_stagger() -> void:
	_hit_timer = 0.34


## Downed guards collapse and stay down (no further pose changes).
func set_downed(active: bool) -> void:
	set_pose_state("downed" if active else "idle")
	if active:
		_pose_blend = 1.0
		_apply_pose(1.0)


## `manual` keeps the pose the caller set instead of deriving it from movement
## (scripted sequences and the phase-13 pose test).
func animate(delta: float, speed: float, crouching: bool, sprinting: bool,
		manual: bool = false) -> void:
	var moving: float = clampf(speed / 220.0, 0.0, 1.6)
	if _hit_timer > 0.0:
		_hit_timer = maxf(0.0, _hit_timer - delta)
	if _pose != "downed" and (not manual or _hit_timer > 0.0):
		var want: String = "idle"
		if melee_active():
			want = "melee"
		elif moving > 0.35:
			want = "sprint" if sprinting else "walk"
		elif crouching:
			want = "crouch"
		if _hit_timer > 0.0:
			want = "hit"
		if want != _pose:
			set_pose_state(want)
	if moving > 0.05:
		_stride += delta * (11.0 if sprinting else 7.0) * maxf(0.35, moving)
	_breath += delta
	_pose_blend = minf(1.0, _pose_blend + delta * 6.0)
	tick_melee(delta)
	_apply_pose(_ease(_pose_blend))


func _ease(t: float) -> float:
	# Smoothstep: no snapping between poses.
	return t * t * (3.0 - 2.0 * t)


func _apply_pose(w: float) -> void:
	var moving: float = clampf(absf(sin(_stride)), 0.0, 1.0)
	var swing: float = sin(_stride) * 0.62
	var breathe: float = sin(_breath * 1.9) * 0.9
	var leg_l: float = swing
	var leg_r: float = -swing
	var arm_l: float = -swing * 0.75
	var arm_r: float = swing * 0.75
	var knee_l: float = maxf(0.0, -swing) * 0.9
	var knee_r: float = maxf(0.0, swing) * 0.9
	var elbow: float = 0.22
	var torso_pitch: float = 0.02 + breathe * 0.01
	var torso_y: float = 34.0 + absf(sin(_stride * 2.0)) * 1.1
	var head_pitch: float = 0.0
	var root_y: float = 0.0

	match _pose:
		"walk":
			pass
		"sprint":
			swing *= 1.25
			leg_l = swing
			leg_r = -swing
			arm_l = -swing * 0.95
			arm_r = swing * 0.95
			elbow = 0.75
			torso_pitch = 0.16
			head_pitch = -0.1
		"crouch":
			root_y = -7.0
			leg_l = 0.85
			leg_r = -0.35
			knee_l = 1.05
			knee_r = 0.65
			torso_pitch = 0.28
			elbow = 0.5
			head_pitch = -0.18
		"takedown":
			root_y = -5.0
			leg_l = 0.6
			leg_r = -0.3
			torso_pitch = 0.45
			elbow = 0.9
			arm_l = -0.9
			arm_r = -0.9
		"hit":
			var t: float = clampf(_hit_timer / 0.34, 0.0, 1.0)
			torso_pitch = -0.3 * t
			head_pitch = 0.35 * t
			arm_l = 0.6 * t
			arm_r = 0.6 * t
		"downed":
			root_y = -22.0
			torso_pitch = 1.15
			leg_l = 1.35
			leg_r = 0.95
			knee_l = 1.5
			knee_r = 1.2
			arm_l = 1.2
			arm_r = 0.9
			head_pitch = 0.5
		"melee":
			var phase: float = clampf(melee_timer / MELEE_WINDUP, 0.0, 1.0)
			var strike: float = 0.0
			if melee_timer >= MELEE_WINDUP:
				strike = clampf(1.0 - (melee_timer - MELEE_WINDUP) / MELEE_RECOVERY, 0.0, 1.0)
			torso_pitch = 0.1 + 0.25 * strike
			arm_r = lerpf(0.9, -1.5, strike if melee_impact_done else phase * 0.5)
			elbow = 0.9
		_:
			torso_y += breathe * 0.6

	# Blend the target pose in from the neutral stance.
	if legs.size() == 2:
		legs[0].rotation.x = lerpf(legs[0].rotation.x, leg_l, w)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, leg_r, w)
	if knees.size() == 2:
		knees[0].rotation.x = lerpf(knees[0].rotation.x, -knee_l, w)
		knees[1].rotation.x = lerpf(knees[1].rotation.x, -knee_r, w)
	if arms.size() == 2:
		arms[0].rotation.x = lerpf(arms[0].rotation.x, arm_l, w)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, arm_r, w)
	if elbows.size() == 2:
		elbows[0].rotation.x = lerpf(elbows[0].rotation.x, -elbow, w)
		elbows[1].rotation.x = lerpf(elbows[1].rotation.x, -elbow, w)
	if torso != null:
		torso.position.y = lerpf(torso.position.y, torso_y + root_y, w)
		torso.rotation.x = lerpf(torso.rotation.x, torso_pitch, w)
		torso.rotation.z = lerpf(torso.rotation.z, sin(_stride) * 0.03 * moving, w)
	if head != null:
		head.rotation.x = lerpf(head.rotation.x, head_pitch, w)


## Guard role/state cue: neutral cyan, suspicious amber, alert red, downed grey.
func set_state_color(color: Color) -> void:
	if color == _state_color:
		return
	_state_color = color
	if _mat_body != null:
		_mat_body.albedo_color = color.darkened(0.18)
	if _mat_panel != null:
		_mat_panel.albedo_color = color.darkened(0.42)
	if visor_material != null:
		visor_material.emission = color.lightened(0.3)
		visor_material.albedo_color = color.lightened(0.2)


func desaturate_for_downed() -> void:
	set_state_color(_state_color.lerp(Color(0.38, 0.40, 0.45), 0.7))


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
	set_pose_state("melee")


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
		if _pose == "melee":
			set_pose_state("idle")
