extends SceneTree
## Phase 3D-13: visual / camera / touch ergonomics pass.
## Covers shoulder-TPS framing at three aspect ratios, humanoid rig poses and
## the melee impact frame, dressing budget caps, the hybrid joystick cycle,
## touch ownership and the HUD/stick separation.

var _checks: int = 0
var _fails: int = 0
var _main: Node = null


func _initialize() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS: ", label)
	else:
		_fails += 1
		print("  FAIL: ", label)


## Analytic NDC (-1..1, y up) for a world point at a given aspect ratio.
func _ndc(cam: Camera3D, point: Vector3, aspect: Vector2i) -> Vector2:
	var view: Vector3 = cam.global_transform.affine_inverse() * point
	var depth: float = -view.z
	if depth <= 0.01:
		return Vector2(99, 99)
	var aspect_ratio: float = float(aspect.x) / float(aspect.y)
	var tan_half: float = tan(deg_to_rad(cam.fov) * 0.5)
	return Vector2((view.x / depth) / (tan_half * aspect_ratio), (view.y / depth) / tan_half)


## Runs the rig's own animation tick without a live actor driving it.
func _drive(rig, ticks: int, delta: float = 0.016) -> void:
	for i in range(ticks):
		rig.animate(delta, 0.0, false, false, true)


func _inside(ndc: Vector2) -> bool:
	return absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0


func _finish() -> void:
	if _fails == 0:
		print("3D PHASE-13 TEST: all checks passed (%d checks)" % _checks)
		print("3D PHASE-13 TEST: %d PASS / 0 FAIL" % _checks)
		quit(0)
	else:
		print("3D PHASE-13 TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
		quit(1)


func _step(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _run() -> void:
	_main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(_main)
	await _step(12)

	var player: CharacterBody3D = _main.player
	var rig: Node3D = player.get_node_or_null("CameraRig")
	var spring: SpringArm3D = player.get_node_or_null("CameraRig/SpringArm3D")
	var camera: Camera3D = player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	_check(rig != null and spring != null and camera != null, "camera rig, spring arm and camera exist")
	if rig == null or spring == null or camera == null:
		_finish()
		return

	# ---------------------------------------------------------------- camera --
	_check(spring.spring_length >= 200.0 and spring.spring_length <= 260.0,
		"spring length sits in the 4-5 unit shoulder range (%.0f)" % spring.spring_length)
	_check(absf(rig.shoulder_offset() - 40.0) < 0.01,
		"shoulder offset is applied to the arm (%.1f)" % rig.shoulder_offset())
	_check(absf(rig.pitch) > 0.1 and rig.pitch < 0.0,
		"default pitch looks slightly down (%.2f rad)" % rig.pitch)
	_check(rig.pitch >= -0.96 - 0.001 and rig.pitch <= 0.61 + 0.001,
		"default pitch inside the clamp range")
	rig.rotate_camera(0.0, -10.0)
	_check(rig.pitch >= -0.96 - 0.001, "pitch clamps at the downward limit (%.2f)" % rig.pitch)
	rig.rotate_camera(0.0, 10.0)
	_check(rig.pitch <= 0.61 + 0.001, "pitch clamps at the upward limit (%.2f)" % rig.pitch)
	rig.pitch = -0.30
	rig.apply_rotation()

	# Framing is measured from a known open cell facing -Z, so the claim is
	# about the rig, not about wherever the spawn happened to be.
	for guard in _main.enemies():
		guard.set_physics_process(false)
	player.global_position = _main.level_root.cell_to_world(Vector2i(6, 13))
	player.velocity = Vector3.ZERO
	rig.yaw = 0.0
	rig.pitch = -0.30
	rig.apply_rotation()
	await _step(20)
	var body_center: Vector3 = player.global_position + Vector3(0, 40, 0)
	# Analytic NDC so the framing claim holds at any window size.
	var corridor_ahead: Vector3 = player.global_position + Vector3(0, 0, -180)
	for aspect in [Vector2i(1280, 720), Vector2i(2340, 1080), Vector2i(2400, 1080)]:
		var ndc_body: Vector2 = _ndc(camera, body_center, aspect)
		var ndc_ahead: Vector2 = _ndc(camera, corridor_ahead, aspect)
		var ndc_sky: Vector2 = _ndc(camera, player.global_position + Vector3(0, 900, -4000), aspect)
		_check(_inside(ndc_body), "player silhouette is on screen at %dx%d" % [aspect.x, aspect.y])
		_check(_inside(ndc_ahead), "corridor ahead is on screen at %dx%d" % [aspect.x, aspect.y])
		var ndc_horizon: Vector2 = _ndc(camera,
			camera.global_position + Vector3(0, 0, -4000), aspect)
		_check(ndc_horizon.y >= 0.35,
			"the horizon sits in the top of the frame, not mid-screen at %dx%d (%.2f)"
			% [aspect.x, aspect.y, ndc_horizon.y])
		_check(_ndc(camera, player.global_position + Vector3(0, 0, -600), aspect).y < 1.0,
			"the floor ahead is framed, not cut off at %dx%d" % [aspect.x, aspect.y])
		_check(camera.global_transform.basis.z.y > -0.35,
			"camera forward does not point into the floor at %dx%d" % [aspect.x, aspect.y])

	_check(spring.get_hit_length() > 150.0, "spring arm is not collapsed in the open (%.0f)"
		% spring.get_hit_length())
	for guard in _main.enemies():
		guard.set_physics_process(true)

	# ------------------------------------------------------------------- rig --
	# A standalone rig: the live player rig is driven by its own animate() loop,
	# which would overwrite every pose the test sets.
	var host := Node3D.new()
	root.add_child(host)
	var prig = CharacterRig.build_player(host)
	_check(prig != null, "player rig exists")
	if prig != null:
		_check(prig.parts.size() >= 18 and prig.parts.size() <= 24,
			"humanoid rig uses a deliberate part count (%d meshes)" % prig.parts.size())
		var mats := {}
		for mi in prig.parts:
			if mi.material_override != null:
				mats[mi.material_override.get_instance_id()] = true
		_check(mats.size() <= 5, "rig shares materials instead of one per limb (%d)" % mats.size())
		_check(prig.knees.size() == 2 and prig.elbows.size() == 2,
			"rig has knee and elbow joints")
		_check(prig.visor_material != null and prig.visor_material.emission_enabled,
			"visor/eye strip is emissive")
		prig.set_pose_state("walk")
		_drive(prig, 8)
		_check(prig.pose_state() == "walk", "rig enters the walk pose")
		prig.set_pose_state("sprint")
		_drive(prig, 8)
		_check(prig.pose_state() == "sprint", "rig enters the sprint pose")
		_check(prig.elbows[0].rotation.x < -0.5, "sprint pose actually bends the arms")
		prig.set_pose_state("crouch")
		_drive(prig, 8)
		_check(prig.pose_state() == "crouch", "rig enters the crouch pose")
		prig.set_pose_state("downed")
		_drive(prig, 8)
		_check(prig.pose_state() == "downed", "rig enters the downed pose")
		_check(prig.torso.rotation.x > 0.4, "downed pose actually collapses the torso")
		prig.set_pose_state("idle")
		prig.play_hit_stagger()
		_drive(prig, 1)
		_check(prig.pose_state() == "hit", "hit stagger interrupts the current pose")
		prig._hit_timer = 0.0
		prig.set_pose_state("idle")
		_drive(prig, 4)

		# melee keeps the 3D-11 impact frame
		prig.start_melee()
		_check(prig.melee_active() and prig.pose_state() == "melee", "melee starts a windup pose")
		_check(not prig.melee_impact_frame(), "no impact during the windup")
		prig.tick_melee(CharacterRig.MELEE_WINDUP + 0.01)
		_check(prig.melee_impact_frame(), "impact frame fires exactly at the windup end")
		_check(not prig.melee_impact_frame(), "impact frame fires only once")
		prig.tick_melee(CharacterRig.MELEE_RECOVERY + 0.05)
		_check(not prig.melee_active(), "melee releases after the recovery")

	# -------------------------------------------------------------- dressing --
	var dressing = _main.dressing
	if dressing == null:
		print("    [dbg] dressing=", dressing, " children=", _main.get_child_count())
	_check(dressing != null, "neon dressing layer exists")
	if dressing != null:
		var budget: Dictionary = dressing.budget_report()
		_check(bool(budget["within_budget"]), "dressing stays inside its budget")
		_check(int(budget["real_lights"]) <= NeonDressing.MAX_REAL_LIGHTS,
			"real light count capped (%d)" % int(budget["real_lights"]))
		_check(int(budget["dressing_meshes"]) <= NeonDressing.MAX_DRESSING_MESHES,
			"dressing mesh count capped (%d)" % int(budget["dressing_meshes"]))
		_check(int(budget["dressing_meshes"]) > 100,
			"dressing actually breaks up the blockout (%d meshes)" % int(budget["dressing_meshes"]))
		_check(int(budget["multimesh_batches"]) >= 3,
			"repeating dressing is batched into multimeshes (%d)" % int(budget["multimesh_batches"]))
		_check(bool(budget["fog_enabled"]), "distance fog hides the map edge")
		var lights := 0
		var shadowed := 0
		for child in dressing.get_children():
			if child is OmniLight3D:
				lights += 1
				if (child as OmniLight3D).shadow_enabled:
					shadowed += 1
		_check(shadowed == 0, "no realtime shadows were introduced (%d lights)" % lights)
		var env: Environment = _main.get_node("WorldEnvironment").environment
		_check(env.fog_enabled, "environment fog is enabled")
		_check(env.ambient_light_energy <= 0.5, "ambient is no longer a flat wash (%.2f)"
			% env.ambient_light_energy)

	# ------------------------------------------------------------- joystick --
	var layer: Control = _main.get_node("UI/TouchLayer")
	layer.visible = true
	layer._layout_buttons()
	await _step(2)
	var home: Vector2 = layer._stick_home
	_check(home.x > 60.0 and home.y > 0.0, "stick home is bottom-left (%.0f,%.0f)" % [home.x, home.y])
	_check(not layer._joystick_visible, "stick rests in its fixed home when untouched")
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.pressed = true
	touch.position = Vector2(home.x + 180.0, home.y - 120.0)
	layer._input(touch)
	await _step(1)
	_check(layer._joystick_visible, "touching the left half activates the stick")
	_check(layer._stick_base.distance_to(touch.position) < 1.0,
		"the base relocates to the finger")
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = touch.position + Vector2(60.0, 0.0)
	layer._input(drag)
	await _step(1)
	_check(layer.get_movement_vector().length() > 0.2,
		"dragging the relocated base produces movement input")
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.pressed = false
	release.position = drag.position
	layer._input(release)
	await _step(2)
	_check(not layer._joystick_visible, "release ends the stick")
	_check(layer._stick_returning, "release starts the return-home easing")
	# Headless frames are sub-millisecond, so drive the ease with a real delta.
	for i in range(12):
		layer._process(0.2)
	_check(layer._stick_base.distance_to(home) < 1.0, "the base eases back to its fixed home")
	_check(not layer._stick_returning, "the return easing settles")

	# --------------------------------------------------------------- touches --
	for aspect in [Vector2i(1280, 720), Vector2i(2340, 1080), Vector2i(2400, 1080)]:
		root.size = aspect
		await _step(2)
		layer._layout_buttons()
		var size := Vector2(aspect)
		_check(layer.is_position_owned(Vector2(size.x * 0.25, size.y * 0.5)),
			"left half belongs to the stick at %dx%d" % [aspect.x, aspect.y])
		_check(not layer.is_position_owned(Vector2(size.x * 0.82, size.y * 0.45)),
			"right half stays camera territory at %dx%d" % [aspect.x, aspect.y])
		_check(layer.is_position_owned(layer.button_center("interact")),
			"USE owns its own touch at %dx%d" % [aspect.x, aspect.y])
		_check(layer.is_position_owned(layer.button_center("crouch")),
			"CROUCH owns its own touch at %dx%d" % [aspect.x, aspect.y])
		# no overlap between any two buttons
		var names: Array = layer._buttons.keys()
		var overlaps: int = 0
		for i in range(names.size()):
			for j in range(i + 1, names.size()):
				var a: Dictionary = layer._buttons[names[i]]
				var b: Dictionary = layer._buttons[names[j]]
				if a["center"].distance_to(b["center"]) < a["radius"] + b["radius"]:
					overlaps += 1
		_check(overlaps == 0, "no two buttons overlap at %dx%d" % [aspect.x, aspect.y])
		# HUD weapon panel must stay out of the stick zone
		var panel: Control = _main.hud.weapon_panel
		var panel_rect := Rect2(panel.global_position, panel.size)
		var stick_center: Vector2 = layer._stick_home
		var stick_radius: float = layer.JOYSTICK_MAX_RADIUS
		_check(not panel_rect.has_point(stick_center),
			"HUD weapon panel does not sit on the stick at %dx%d" % [aspect.x, aspect.y])
		_check(panel_rect.position.y + panel_rect.size.y
				< stick_center.y - stick_radius * 0.55,
			"weapon panel clears the stick's upper edge at %dx%d" % [aspect.x, aspect.y])
		_check(_main.hud.hud_scale >= 1.2,
			"HUD scale default is legible on phones (%.2f)" % _main.hud.hud_scale)
		_check(panel_rect.size.x > 100.0, "weapon panel has a readable width (%.0f)"
			% panel_rect.size.x)

	# ------------------------------------------------------------- restart ----
	_main.load_layout("legacy")
	await _step(10)
	_check(_main.dressing.get_child_count() > 0, "dressing rebuilds after a restart")
	var before: int = _main.dressing.budget_report()["dressing_meshes"]
	_main.load_layout("legacy")
	await _step(10)
	_check(int(_main.dressing.budget_report()["dressing_meshes"]) == before,
		"restart does not pile up dressing meshes (%d)" % before)
	var audio_nodes: int = 0
	for child in _main.get_children():
		if child is SpatialAudio:
			audio_nodes += 1
	_check(audio_nodes == 1, "exactly one SpatialAudio after restart")

	_finish()
