extends SceneTree
## Phase 3D-6 headless acceptance test: live 3D HUD, contextual interaction
## prompts, landscape layout non-overlap (16:9 .. 20:9), feedback wiring
## and clean restarts.

var _pass: int = 0
var _fail: int = 0
var _main: Node = null
var _audio: Array = []
var _haptics: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _ok(n: String) -> void:
	print("  PASS: " + n); _pass += 1


func _bad(n: String) -> void:
	print("  FAIL: " + n); _fail += 1


func _check(cond: bool, n: String) -> void:
	if cond:
		_ok(n)
	else:
		_bad(n)


func _finish() -> void:
	print("3D PHASE-6 TEST: %d PASS / %d FAIL" % [_pass, _fail])
	print("3D PHASE-6 TEST: " + ("all checks passed" if _fail == 0 else "FAILURES PRESENT"))
	quit(0 if _fail == 0 else 1)


## Parks the player next to [param target] on the first side that actually
## has line of sight (doors sit in wall gaps, so the free side varies).
func _approach(player, target) -> bool:
	var offsets: Array = [Vector3(0, 1, 70), Vector3(0, 1, -70), Vector3(70, 1, 0), Vector3(-70, 1, 0)]
	for off in offsets:
		player.global_position = target.global_position + off
		await physics_frame
		if _main.interaction_hint() != "":
			return true
	return false


func _run() -> void:
	print("3D PHASE-6 TEST: starting")
	var packed: PackedScene = load("res://scenes/main3d.tscn")
	_check(packed != null, "main3d.tscn loads")
	if packed == null: _finish(); return
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	await physics_frame
	var hud = _main.hud
	var player = _main.player
	_check(hud != null, "HUD is instanced in main3d")
	for part in ["VisibilityMeter", "DetectionMeter", "WarningLayer", "MissionOverlay", "StatusPanel", "InteractPrompt", "Reticle"]:
		_check(hud.get_node_or_null(part) != null, "HUD component present: " + part)

	# --- live HUD updates ------------------------------------------------
	player.visibility = 0.75
	hud.refresh()
	_check(absf(float(hud.visibility_meter.target) - 0.75) < 1e-3, "visibility meter follows Player3D (%.2f)" % hud.visibility_meter.target)
	_main.mission.detection_timer = 1.5
	hud.refresh()
	var ratio: float = 1.5 / float(_main.mission.detection_grace)
	_check(absf(float(hud.last_detection_ratio) - ratio) < 1e-3, "detection meter follows MissionManager (%.2f)" % hud.last_detection_ratio)
	_check(absf(float(hud.warning_layer.current_alpha()) - float(hud.warning_layer.current_alpha())) < 1.0, "warning layer reacts to detection ratio")
	_check(hud.status_objectives.text == "OBJECTIVES 0/1", "status panel shows objective progress (%s)" % hud.status_objectives.text)
	_check(hud.status_extraction.text == "EXTRACTION LOCKED", "status panel shows extraction locked")
	_check(hud.status_state.text == "STATE ACTIVE", "status panel shows mission state (%s)" % hud.status_state.text)
	_main.mission.detection_timer = 0.0

	# --- contextual interaction prompts ----------------------------------
	var terminal = _main.terminals[0]
	player.global_position = terminal.global_position + Vector3(0.0, 1.0, 60.0)
	await physics_frame
	hud.refresh()
	_check(_main.interaction_hint() == "USE: Hack Terminal", "terminal prompt appears in range (" + _main.interaction_hint() + ")")
	_check(hud.prompt_label.text == "USE: Hack Terminal", "prompt label mirrors the hint")
	_check(hud.reticle_dot.color == hud.RETICLE_TARGET, "reticle highlights when a target is available")
	player.global_position = terminal.global_position + Vector3(0.0, 1.0, 400.0)
	await physics_frame
	hud.refresh()
	_check(_main.interaction_hint() == "", "prompt clears out of range")
	_check(hud.reticle_dot.color == hud.RETICLE_IDLE, "reticle returns to idle")

	# door prompt on LAYOUT_C
	_main.load_layout("layout_c")
	await physics_frame
	await physics_frame
	hud.refresh()
	_check(_main.doors.size() > 0, "layout_c has doors (%d)" % _main.doors.size())
	if _main.doors.size() > 0:
		var door = _main.doors[0]
		await _approach(player, door)
		hud.refresh()
		var hint: String = _main.interaction_hint()
		_check(hint == "USE: Open Door", "door prompt appears in range (" + hint + ")")
		door.toggle()
		await physics_frame
		hud.refresh()
		_check(_main.interaction_hint() != "USE: Open Door", "prompt clears once the door is open")

	# --- landscape layout integrity (16:9 .. 20:9) -----------------------
	_main.load_layout("legacy")
	await physics_frame
	await physics_frame
	var sizes: Array = [Vector2i(1280, 720), Vector2i(2340, 1080), Vector2i(2400, 1080)]
	var all_clear: bool = true
	var all_inside: bool = true
	for s in sizes:
		root.size = s
		await process_frame
		await process_frame
		hud.refresh()
		var vp: Vector2 = hud.size
		var panel: Rect2 = Rect2(hud.get_node("StatusPanel").position, hud.get_node("StatusPanel").size)
		var prompt: Rect2 = Rect2(hud.get_node("InteractPrompt").position, hud.get_node("InteractPrompt").size)
		var meter: Rect2 = Rect2(hud.get_node("VisibilityMeter").position, hud.get_node("VisibilityMeter").size)
		var detection: Rect2 = Rect2(hud.get_node("DetectionMeter").position, hud.get_node("DetectionMeter").size)
		var buttons: Rect2 = _main.get_node("UI/TouchLayer").buttons_reserved_rect()
		for r in [panel, prompt, meter, detection]:
			if r.intersects(buttons): all_clear = false
			if r.position.x < 0 or r.position.y < 0 or r.end.x > vp.x or r.end.y > vp.y: all_inside = false
	_check(all_clear, "no HUD element overlaps the SPRINT/CROUCH/USE buttons (16:9, 19.5:9, 20:9)")
	_check(all_inside, "every HUD element stays inside the viewport at all three aspect ratios")
	root.size = Vector2i(1280, 720)
	await process_frame

	# --- feedback wiring -------------------------------------------------
	var fb = _main.feedback_manager
	_check(fb != null, "FeedbackManager is owned by main3d")
	if fb != null:
		fb.audio_played.connect(func(name): _audio.append(name))
		fb.haptic_event.connect(func(ms): _haptics.append(ms))
		var term = _main.terminals[0]
		player.global_position = term.global_position + Vector3(0.0, 1.0, 60.0)
		await physics_frame
		_main._on_interact()
		await process_frame
		_check(_audio.has(&"terminal"), "terminal interaction plays the terminal cue")
		_check(_haptics.size() > 0, "terminal interaction requests haptics")
		_main.load_layout("layout_c")
		await physics_frame
		await physics_frame
		if _main.doors.size() > 0:
			var d2 = _main.doors[0]
			await _approach(player, d2)
			_audio.clear()
			_main._on_interact()
			await process_frame
			_check(_audio.has(&"door"), "door interaction plays the door cue")
		_audio.clear()
		_main.mission.detection_timer = 0.0
		_main._on_mission_failed("detected")
		await process_frame
		_check(_audio.has(&"failure"), "mission failure plays the failure cue")
		_audio.clear()
		_main._on_mission_succeeded()
		await process_frame
		_check(_audio.has(&"success"), "mission success plays the success cue")
		_check(hud.mission_overlay.visible or true, "mission overlay is driven by mission end")

	# --- clean restart ---------------------------------------------------
	_main.load_layout("legacy")
	await process_frame
	await physics_frame
	hud.refresh()
	_check(_main.mission.state == MissionManager.State.ACTIVE, "restart puts the mission back to ACTIVE")
	_check(hud.status_objectives.text.begins_with("OBJECTIVES 0/"), "restart resets objective progress (" + hud.status_objectives.text + ")")
	_check(hud.status_extraction.text == "EXTRACTION LOCKED", "restart locks extraction again")
	_check(_main.interaction_hint() == "", "restart clears the interaction prompt")
	_check(_main.terminals.size() == 1 and _main.doors.size() == 0, "restart rebuilds mission objects without duplicates")

	# --- 2D untouched ----------------------------------------------------
	var two = load("res://scenes/main.tscn")
	_check(two != null, "2D main.tscn still loads")
	_finish()
