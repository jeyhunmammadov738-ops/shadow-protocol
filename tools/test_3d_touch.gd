extends SceneTree
## Phase 3D-7.1 device regression test: simulated Android touch.
##
## Reproduces the on-device blocker (left-half drag never moved Player3D)
## by pushing real InputEventScreenTouch/Drag events through the engine,
## then drives the whole gameplay loop with the touch buttons only.

var _checks: int = 0
var _fails: int = 0
var _main: Node3D = null
var _tl: Control = null
var _player: CharacterBody3D = null


func _initialize() -> void:
	call_deferred("_run")


func _ok(n: String) -> void:
	_checks += 1
	print("  PASS: ", n)


func _bad(n: String) -> void:
	_checks += 1
	_fails += 1
	print("  FAIL: ", n)


func _check(c: bool, n: String) -> void:
	if c:
		_ok(n)
	else:
		_bad(n)


func _frames(n: int) -> void:
	for _i in range(n):
		await physics_frame


func _touch(pos: Vector2, pressed: bool, index: int = 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func _drag(pos: Vector2, index: int = 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	root.push_input(e, true)


func _run() -> void:
	print("3D TOUCH TEST: starting")
	_main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await _frames(4)
	_tl = _main.get_node("UI/TouchLayer")
	_player = _main.player
	# Headless reports no touchscreen, so the layer hides itself; on Android
	# it is visible. Force the device state for the simulation.
	_tl.visible = true
	await process_frame

	_check(_player._touch_layer == _tl, "Player3D receives the touch layer (device blocker fix)")
	_check(_tl.button_center("sprint") != Vector2.ZERO, "action buttons expose their touch centres")

	# --- left-half drag must move the player -----------------------------
	var vp: Vector2 = _tl.get_viewport_rect().size
	var start: Vector3 = _player.global_position
	_touch(Vector2(vp.x * 0.14, vp.y * 0.78), true)
	await process_frame
	_drag(Vector2(vp.x * 0.14 + 120.0, vp.y * 0.78), 0)
	await process_frame
	var vec: Vector2 = _tl.get_movement_vector()
	_check(vec.length() > 0.5, "left-half drag activates the floating joystick (|v|=%.2f)" % vec.length())
	await _frames(30)
	var moved: float = (_player.global_position - start).length()
	_check(moved > 40.0, "joystick input displaces Player3D on the 3D floor (%.0f units)" % moved)
	_touch(Vector2(vp.x * 0.14 + 120.0, vp.y * 0.78), false)
	await _frames(6)
	_check(_tl.get_movement_vector().length() < 0.01, "releasing the drag recentres the joystick")
	var still: Vector3 = _player.global_position
	await _frames(12)
	_check((_player.global_position - still).length() < 12.0, "player stops after release")

	# --- right-half drag rotates the camera ------------------------------
	var rig = _player.get_node("CameraRig")
	var yaw_before: float = rig.yaw
	_touch(Vector2(vp.x * 0.82, vp.y * 0.5), true, 1)
	await process_frame
	_drag(Vector2(vp.x * 0.82 + 140.0, vp.y * 0.5), 1)
	await process_frame
	_check(absf(rig.yaw - yaw_before) > 0.05, "right-half drag still rotates the camera")
	_touch(Vector2(vp.x * 0.82 + 140.0, vp.y * 0.5), false, 1)

	# --- SPRINT / CROUCH buttons -----------------------------------------
	_touch(_tl.button_center("sprint"), true, 2)
	await _frames(3)
	_check(_player.sprinting, "SPRINT button makes the player sprint")
	_touch(_tl.button_center("sprint"), false, 2)
	await _frames(3)
	_check(not _player.sprinting, "releasing SPRINT stops sprinting")
	_touch(_tl.button_center("crouch"), true, 3)
	_touch(_tl.button_center("crouch"), false, 3)
	await _frames(3)
	_check(_player.crouching, "CROUCH button latches crouch")
	_touch(_tl.button_center("crouch"), true, 3)
	_touch(_tl.button_center("crouch"), false, 3)
	await _frames(3)
	_check(not _player.crouching, "CROUCH toggles back to standing")

	# --- USE button drives the real gameplay loop ------------------------
	_main.load_layout("layout_c")
	await _frames(6)
	var door = _main.doors[0]
	var side: Vector3 = await _approach(door)
	_check(side != Vector3.ZERO, "player can stand in line of sight of a door")
	if side != Vector3.ZERO:
		_player.global_position = side
		await _frames(2)
		_check(_main.interaction_hint().begins_with("USE:"), "USE prompt is live for the door")
		_press_use()
		await _frames(3)
		_check(door.is_open(), "USE button opens the door")
		_press_use()
		await _frames(3)
		_check(not door.is_open(), "USE button closes it again")

	var term = _main.terminals[0]
	var term_side: Vector3 = await _approach(term, 50.0)
	_check(term_side != Vector3.ZERO, "player can stand in line of sight of a terminal")
	if term_side != Vector3.ZERO:
		_player.global_position = term_side
		await _frames(2)
		_check(_main.find_interactable() == term, "terminal is the resolved interaction target")
		_press_use()
		await _frames(3)
		_check(term.is_completed(), "USE button hacks the terminal")

	# Finish the remaining objectives by touch, then extract.
	for t in _main.terminals:
		if not t.is_completed():
			var p: Vector3 = await _approach(t)
			if p != Vector3.ZERO:
				_player.global_position = p
				await _frames(2)
				_press_use()
				await _frames(2)
	await _frames(4)
	_check(_main.mission.objectives_done() == _main.mission.objectives_total(),
		"every objective completes through the USE button")
	_check(_main.mission.extraction_available(), "extraction unlocks once objectives are done")
	_player.global_position = _main.extraction.global_position
	await _frames(8)
	_check(_main.mission.state == MissionManager.State.SUCCEEDED, "mission succeeds at extraction")

	# --- spawn framing ---------------------------------------------------
	_main.load_layout("legacy")
	# The lift-over camera settles over a few frames; measure the steady state.
	await _frames(36)
	var walls: Dictionary = _main.level_data.get("wall_cells", {})
	var cell: Vector2i = _main.level_root.world_to_cell(_player.global_position)
	var ahead: Vector2i = cell + Vector2i(0, -1)
	var fwd: Vector3 = -_player.global_transform.basis.z
	var facing_open: bool = not walls.has(ahead) or not walls.has(cell + Vector2i(1, 0)) or not walls.has(cell + Vector2i(0, 1)) or not walls.has(cell + Vector2i(-1, 0))
	_check(facing_open, "spawn faces an open corridor instead of a corner wall")
	_check(absf(fwd.y) < 0.1, "spawn facing is horizontal")
	var cam: Camera3D = _player.get_node("CameraRig/SpringArm3D/Camera3D")
	var dist: float = cam.global_position.distance_to(_player.global_position)
	_check(dist > 90.0, "camera keeps a playable distance from the capsule (%.0f)" % dist)

	print("3D TOUCH TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D TOUCH TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D TOUCH TEST: all checks passed")
		quit(0)


func _press_use() -> void:
	var c: Vector2 = _tl.button_center("interact")
	if c == Vector2.ZERO:
		return
	_touch(c, true, 7)
	_touch(c, false, 7)


## Returns a stand position with line of sight to [param target], or ZERO.
func _approach(target, radius: float = 70.0) -> Vector3:
	var offsets: Array = [Vector3(0, 1, radius), Vector3(0, 1, -radius),
		Vector3(radius, 1, 0), Vector3(-radius, 1, 0),
		Vector3(radius * 0.7, 1, radius * 0.7), Vector3(-radius * 0.7, 1, -radius * 0.7)]
	for off in offsets:
		_player.global_position = target.global_position + off
		await _frames(2)
		if _main.interaction_hint() != "":
			return _player.global_position
	return Vector3.ZERO
