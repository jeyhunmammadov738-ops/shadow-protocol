extends SceneTree
## Shadow Protocol - Phase 3D-1 headless acceptance test.
##
## Verifies the 3D skeleton end to end without a display or device:
##   - main3d.tscn loads and wires player + camera rig
##   - the spring-arm camera sits behind and above the player
##   - camera-relative movement, grounding and crouch posture work
##   - camera rotation is clamped and NEVER starts on a touch that belongs
##     to the shared touch layer (joystick zone or SPRINT/CROUCH/USE)
##   - the untouched 2D scenes still load exactly as before
##
## Usage: godot --headless --path . --script res://tools/test_3d_phase1.gd

var _pass: int = 0
var _fail: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _ok(message: String) -> void:
	print("  PASS: " + message)
	_pass += 1


func _bad(message: String) -> void:
	print("  FAIL: " + message)
	_fail += 1


func _check(condition: bool, message: String) -> void:
	if condition:
		_ok(message)
	else:
		_bad(message)


func _finish() -> void:
	print("3D PHASE-1 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	if _fail == 0:
		print("3D PHASE-1 TEST: all checks passed")
	quit(0 if _fail == 0 else 1)


func _step(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _run() -> void:
	print("3D PHASE-1 TEST: starting")
	var packed: PackedScene = load("res://scenes/main3d.tscn")
	_check(packed != null, "main3d.tscn loads")
	if packed == null:
		_finish()
		return

	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var player: CharacterBody3D = main.get_node_or_null("Player3D") as CharacterBody3D
	_check(player != null, "Player3D exists as CharacterBody3D")
	if player == null:
		_finish()
		return
	var rig: Node3D = player.get_node_or_null("CameraRig") as Node3D
	_check(rig != null and rig.has_method("get_yaw"), "CameraRig exists with rotation API")
	var spring: SpringArm3D = player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	_check(spring != null, "SpringArm3D present")
	var camera: Camera3D = player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	_check(camera != null, "Camera3D present")
	if rig == null or spring == null or camera == null:
		_finish()
		return

	_check(spring.spring_length > 0.0, "spring arm has a positive length")
	_check(spring.collision_mask == 1, "spring arm collides with world layer 1")
	_check(camera.current, "camera is current")

	await _step(20)
	var pivot: Vector3 = rig.global_position
	var cam: Vector3 = camera.global_position
	_check(cam.z > pivot.z + 50.0, "camera sits BEHIND the player (+Z at yaw 0)")
	_check(cam.y > pivot.y + 10.0, "camera sits ABOVE the pivot")
	var dist: float = cam.distance_to(pivot)
	_check(dist > 100.0 and dist <= spring.spring_length + 1.0,
		"camera distance %.1f within spring length %.1f" % [dist, spring.spring_length])

	# --- grounded forward movement (camera-relative) ---
	var start: Vector3 = player.global_position
	player.use_input_override = true
	player.input_override = Vector2(0.0, -1.0)
	await _step(60)
	player.input_override = Vector2.ZERO
	var moved: Vector3 = player.global_position - start
	_check(moved.length() > 80.0, "forward input moves the player (%.1f units)" % moved.length())
	_check(absf(player.global_position.y) < 2.0, "player stays grounded (y = %.2f)" % player.global_position.y)
	_check(moved.z < -40.0, "forward input at yaw 0 moves toward -Z (dz = %.1f)" % moved.z)

	# --- camera-relative basis: yaw -90 deg must move along +X ---
	rig.yaw = -PI * 0.5
	rig.apply_rotation()
	await _step(10)
	var start2: Vector3 = player.global_position
	player.input_override = Vector2(0.0, -1.0)
	await _step(45)
	player.input_override = Vector2.ZERO
	var moved2: Vector3 = player.global_position - start2
	_check(moved2.x > 40.0, "movement follows camera yaw (dx = %.1f)" % moved2.x)
	_check(absf(moved2.z) < absf(moved2.x), "movement is camera-relative, not world-fixed")

	# --- crouch posture ---
	player.set_touch_crouch(true)
	await _step(40)
	var crouched_height: float = (player.get_node("CollisionShape3D") as CollisionShape3D).shape.height
	_check(crouched_height < 70.0, "crouch lowers the capsule (%.1f)" % crouched_height)
	_check(rig.position.y < 55.0, "crouch lowers the camera pivot (%.1f)" % rig.position.y)
	player.set_touch_crouch(false)
	await _step(40)
	var stand_height: float = (player.get_node("CollisionShape3D") as CollisionShape3D).shape.height
	_check(stand_height > 80.0, "standing restores the capsule (%.1f)" % stand_height)

	# --- touch ownership: buttons must never rotate the camera ---
	var touch_layer: Control = main.get_node_or_null("UI/TouchLayer") as Control
	_check(touch_layer != null, "shared 2D touch layer is instanced in main3d")
	if touch_layer != null:
		touch_layer.visible = true
		var screen: Vector2 = main.get_viewport().get_visible_rect().size
		var interact_center: Vector2 = screen - Vector2(110.0, 120.0)
		var crouch_center: Vector2 = screen - Vector2(226.0, 76.0)
		var sprint_center: Vector2 = screen - Vector2(196.0, 192.0)
		_check(not rig.accepts_touch(interact_center), "USE button touch is excluded from camera drag")
		_check(not rig.accepts_touch(crouch_center), "CROUCH button touch is excluded from camera drag")
		_check(not rig.accepts_touch(sprint_center), "SPRINT button touch is excluded from camera drag")
		_check(not rig.accepts_touch(Vector2(100.0, 500.0)), "joystick zone touch is excluded from camera drag")
		var free_spot: Vector2 = Vector2(900.0, 250.0)
		_check(rig.accepts_touch(free_spot), "free right-side touch is accepted for camera drag")

		# A press on the USE button must not change yaw even if dragged.
		var yaw_before: float = rig.get_yaw()
		var press := InputEventScreenTouch.new()
		press.position = interact_center
		press.index = 0
		press.pressed = true
		rig._input(press)
		var drag_on_button := InputEventScreenDrag.new()
		drag_on_button.position = interact_center + Vector2(120.0, 0.0)
		drag_on_button.index = 0
		rig._input(drag_on_button)
		_check(is_equal_approx(rig.get_yaw(), yaw_before), "dragging on the USE button does not rotate the camera")
		var release := InputEventScreenTouch.new()
		release.position = interact_center + Vector2(120.0, 0.0)
		release.index = 0
		release.pressed = false
		rig._input(release)

		# A free right-side drag MUST rotate.
		var press2 := InputEventScreenTouch.new()
		press2.position = free_spot
		press2.index = 1
		press2.pressed = true
		rig._input(press2)
		var drag2 := InputEventScreenDrag.new()
		drag2.position = free_spot + Vector2(100.0, 0.0)
		drag2.index = 1
		rig._input(drag2)
		_check(not is_equal_approx(rig.get_yaw(), yaw_before), "free right-side drag rotates the camera")
		var release2 := InputEventScreenTouch.new()
		release2.position = free_spot + Vector2(100.0, 0.0)
		release2.index = 1
		release2.pressed = false
		rig._input(release2)

	# --- pitch clamp ---
	rig.rotate_camera(0.0, 10.0)
	_check(is_equal_approx(rig.get_pitch(), rig.PITCH_MIN), "pitch clamps at the lower bound")
	rig.rotate_camera(0.0, -10.0)
	_check(is_equal_approx(rig.get_pitch(), rig.PITCH_MAX), "pitch clamps at the upper bound")

	# --- the untouched 2D prototype still loads ---
	var main2d: PackedScene = load("res://scenes/main.tscn")
	_check(main2d != null, "2D main.tscn still loads")
	if main2d != null:
		var inst2d: Node = main2d.instantiate()
		_check(inst2d is Node2D, "2D main root is still Node2D")
		inst2d.free()
	var player2d: PackedScene = load("res://scenes/player.tscn")
	_check(player2d != null, "2D player.tscn still loads")
	if player2d != null:
		var p2: Node = player2d.instantiate()
		_check(p2 is CharacterBody2D, "2D player is still CharacterBody2D")
		p2.free()

	_finish()
