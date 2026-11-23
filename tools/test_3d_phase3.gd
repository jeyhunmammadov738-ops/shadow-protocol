extends SceneTree
## Phase 3D-3 headless acceptance test: numeric 2D/3D stealth parity
## (1e-6) plus live player integration.
##
## Parity is measured against the REAL 2D implementation: the StealthSystem
## autoload and scripts/light_source.gd, not a copy. Identical logical
## inputs are fed to both sides (2D (x, y) <-> 3D (x, 0, y)) and every
## output is compared with TOLERANCE.

const TOLERANCE: float = 1e-6
const SAMPLE_STEP: float = 25.0

var _pass: int = 0
var _fail: int = 0
var _max_delta: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  PASS: " + name)
		_pass += 1
	else:
		print("  FAIL: " + name)
		_fail += 1


func _close(a: float, b: float) -> bool:
	var d: float = absf(a - b)
	if d > _max_delta:
		_max_delta = d
	return d <= TOLERANCE


## Deterministic noise-phase setup: camera yaw zeroed so the override input
## maps to world axes, player parked at the head of the long west column
## (LEGACY column x=1 is clear from row 1 to row 14) with a clean timer.
func _reset_noise_phase(main, player) -> void:
	var rig = player.get_node_or_null("CameraRig")
	if rig != null:
		rig.yaw = 0.0
		rig.pitch = -0.30
		if rig.has_method("apply_rotation"):
			rig.apply_rotation()
	player.global_position = main.level_root.cell_to_world(Vector2i(1, 13))
	player.velocity = Vector3.ZERO
	player._noise_timer = 0.0
	player.use_input_override = true
	player.input_override = Vector2(0, -1)


func _run() -> void:
	print("3D PHASE-3 TEST: starting")
	await process_frame
	var two: Node = root.get_node_or_null("StealthSystem")
	_check(two != null, "2D StealthSystem autoload is present and untouched")

	var three := StealthSystem3D.new()
	root.add_child(three)
	await process_frame

	# Shared configuration: 4 lit cells inside a 6x6 shadow grid.
	var lit := {Vector2i(1, 1): true, Vector2i(2, 1): true, Vector2i(1, 2): true, Vector2i(4, 4): true}
	two.configure(lit, 48.0, Vector2.ZERO, {})
	three.configure(lit, 48.0, Vector3.ZERO, {})

	# --- A. grid illumination parity -------------------------------------
	var grid_ok := true
	var grid_samples := 0
	for gx in range(-1, 7):
		for gy in range(-1, 7):
			var p2 := Vector2(float(gx) * 48.0 + 24.0, float(gy) * 48.0 + 24.0)
			var p3 := Vector3(p2.x, 0.0, p2.y)
			grid_samples += 1
			if not _close(two.grid_illumination_at(p2), three.grid_illumination_at(p3)):
				grid_ok = false
	_check(grid_ok, "grid illumination parity over %d cells" % grid_samples)

	# --- B. quadratic light falloff parity -------------------------------
	var light2 := LightSource.new()
	light2.position = Vector2(120.0, 240.0)
	light2.light_radius = 160.0
	light2.light_intensity = 0.8
	root.add_child(light2)
	var light3 := LightSource3D.new()
	light3.position = Vector3(120.0, 0.0, 240.0)
	light3.light_radius = 160.0
	light3.light_intensity = 0.8
	three.add_child(light3)
	await process_frame
	_check(two.light_count() >= 1, "2D light registered with the 2D system")
	_check(three.light_count() == 1, "3D light registered with the 3D system")

	var light_ok := true
	var light_samples := 0
	var span: int = int(200.0 / SAMPLE_STEP)
	for ix in range(-span, span + 1):
		for iy in range(-span, span + 1):
			var p2 := Vector2(120.0 + float(ix) * SAMPLE_STEP, 240.0 + float(iy) * SAMPLE_STEP)
			var p3 := Vector3(p2.x, 0.0, p2.y)
			light_samples += 1
			if not _close(light2.contribution_at(p2), light3.contribution_at(p3)):
				light_ok = false
	_check(light_ok, "quadratic falloff parity over %d samples" % light_samples)

	# --- C. illumination / visibility parity -----------------------------
	var vis_ok := true
	var vis_samples := 0
	for ix in range(-2, 9):
		for iy in range(-2, 9):
			var p2 := Vector2(float(ix) * 48.0 + 20.0, float(iy) * 48.0 + 20.0)
			var p3 := Vector3(p2.x, 0.0, p2.y)
			if not _close(two.illumination_at(p2), three.illumination_at(p3)):
				vis_ok = false
			for crouch in [false, true]:
				for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
					vis_samples += 1
					if not _close(two.compute_visibility(p2, crouch, s),
							three.compute_visibility(p3, crouch, s)):
						vis_ok = false
	_check(vis_ok, "visibility parity over %d input combinations" % vis_samples)

	# --- D. noise radius parity ------------------------------------------
	var noise_ok := true
	var noise_samples := 0
	for crouch in [false, true]:
		for sprint in [false, true]:
			for s in [0.0, 0.1, 0.33, 0.5, 0.66, 0.9, 1.0]:
				noise_samples += 1
				if not _close(two.noise_radius(crouch, s, sprint),
						three.noise_radius(crouch, s, sprint)):
					noise_ok = false
	_check(noise_ok, "noise radius parity over %d combinations" % noise_samples)

	# --- E. moving light parity ------------------------------------------
	var mov2 := MovingLight.new()
	mov2.light_radius = 150.0
	mov2.light_intensity = 0.7
	mov2.point_a = Vector2(96.0, 96.0)
	mov2.point_b = Vector2(384.0, 240.0)
	mov2.speed = 80.0
	root.add_child(mov2)
	var mov3 := MovingLight3D.new()
	mov3.light_radius = 150.0
	mov3.light_intensity = 0.7
	mov3.point_a = Vector3(96.0, 0.0, 96.0)
	mov3.point_b = Vector3(384.0, 0.0, 240.0)
	mov3.speed = 80.0
	three.add_child(mov3)
	await process_frame
	var mov_ok := true
	for t in [0.0, 0.5, 1.0, 2.5, 4.0, 7.75, 11.0]:
		mov2.set("_elapsed", t)
		mov2._process(0.0)
		mov3.advance_to(t)
		if not (_close(mov2.global_position.x, mov3.global_position.x)
				and _close(mov2.global_position.y, mov3.global_position.z)):
			mov_ok = false
	_check(mov_ok, "moving light path parity at 7 elapsed times")

	# --- F. grid conversion parity ---------------------------------------
	var conv_ok := true
	for p2 in [Vector2(0, 0), Vector2(47.9, 47.9), Vector2(48, 48), Vector2(-1, -1), Vector2(1030.5, 611.2)]:
		var p3 := Vector3(p2.x, 0.0, p2.y)
		var c2: Vector2i = two.world_to_grid(p2)
		var c3: Vector2i = three.world_to_grid(p3)
		if c2 != c3:
			conv_ok = false
		var back2: Vector2 = two.grid_to_world(c2)
		var back3: Vector3 = three.grid_to_world(c3)
		if not (_close(back2.x, back3.x) and _close(back2.y, back3.z)):
			conv_ok = false
	_check(conv_ok, "world<->grid conversion parity (Vector2 <-> Vector3 x,z)")

	# --- G. noise event contract + dedup parity ---------------------------
	var got2: Array = []
	var got3: Array = []
	two.noise_emitted.connect(func(ev): got2.append(ev))
	three.noise_emitted.connect(func(ev): got3.append(ev))
	two.publish_noise(Vector2(96, 96), 220.0, &"player", &"walk")
	two.publish_noise(Vector2(96, 96), 220.0, &"player", &"walk")
	three.publish_noise(Vector3(96, 0, 96), 220.0, &"player", &"walk")
	three.publish_noise(Vector3(96, 0, 96), 220.0, &"player", &"walk")
	_check(got2.size() == 1 and got3.size() == 1, "same-frame dedup parity (1 event each)")
	_check(got3.size() == 1 and got3[0].radius == got2[0].radius
		and got3[0].position.x == 96.0 and got3[0].position.z == 96.0,
		"3D noise event carries mapped position and radius")

	# --- H. live main3d integration --------------------------------------
	var main_scene: PackedScene = load("res://scenes/main3d.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	var player = main.get_node("Player3D")
	_check(main.stealth != null, "main3d owns a StealthSystem3D")
	_check(main.stealth.light_count() >= 1, "layout lamps registered with the 3D core")
	_check(player._stealth == main.stealth, "Player3D is wired to the 3D stealth core")

	var seen: Array = []
	main.stealth.noise_emitted.connect(func(ev): seen.append(ev))
	player.global_position = main.level_root.cell_to_world(Vector2i(6, 13))
	player.velocity = Vector3.ZERO
	player.use_input_override = true
	player.input_override = Vector2(1, 0)
	for i in range(40):
		await physics_frame
	_check(seen.size() >= 1, "walking publishes noise events (%d in ~0.7 s)" % seen.size())
	_check(seen.size() > 0 and absf(seen[0].radius - 220.0) < 60.0,
		"walking noise radius is the 220-unit band (%.0f)" % (seen[0].radius if seen.size() > 0 else -1.0))
	_check(player.visibility >= 0.0 and player.visibility <= 1.0,
		"live visibility stays inside 0..1 (%.3f)" % player.visibility)

	seen.clear()
	_reset_noise_phase(main, player)
	player.set_touch_crouch(true)
	for i in range(30):
		await physics_frame
	_check(seen.size() >= 1 and absf(seen[0].radius - 90.0) < 1e-3,
		"crouched noise radius is exactly 90 (%.1f)" % (seen[0].radius if seen.size() > 0 else -1.0))

	seen.clear()
	_reset_noise_phase(main, player)
	player.set_touch_crouch(false)
	player.set_touch_sprint(true)
	for i in range(30):
		await physics_frame
	_check(seen.size() >= 1 and absf(seen[0].radius - 320.0) < 1e-3,
		"sprint noise radius is exactly 320 (%.1f)" % (seen[0].radius if seen.size() > 0 else -1.0))

	var lit_cells: Dictionary = main.level_data.get("lit_cells", {})
	if lit_cells.size() > 0:
		var lit_cell: Vector2i = lit_cells.keys()[0]
		var lit_vis: float = main.stealth.compute_visibility(
			main.level_root.cell_to_world(lit_cell), false, 0.0)
		var dark_vis: float = main.stealth.compute_visibility(
			main.level_root.cell_to_world(Vector2i(6, 13)), false, 0.0)
		_check(lit_vis > dark_vis, "lit cells read brighter than shadow cells (%.2f > %.2f)" % [lit_vis, dark_vis])

	print("3D PHASE-3 TEST: max numeric delta = " + str(_max_delta) + " (tolerance " + str(TOLERANCE) + ")")
	print("3D PHASE-3 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	if _fail == 0:
		print("3D PHASE-3 TEST: all checks passed")
	quit(1 if _fail > 0 else 0)
