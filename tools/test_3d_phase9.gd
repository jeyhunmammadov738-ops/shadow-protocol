extends SceneTree
## Phase 3D-9: web-parity port tests (weapons, cover, cameras, tripwires,
## facility data). Pure-logic first, then live scene integration.

var _checks: int = 0
var _fails: int = 0


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


func _run() -> void:
	print("3D PHASE-9 TEST: starting")
	_weapons()
	_cover()
	_cameras()
	_tripwires()
	await _facility()
	print("3D PHASE-9 TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D PHASE-9 TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D PHASE-9 TEST: all checks passed")
		quit(0)


func _weapons() -> void:
	var w := WeaponSystem.new()
	_check(WeaponSystem.SLOT_IDS.size() == 6, "six weapon slots exist")
	_check(w.owned_count() == 2, "mission starts with sidearm + knife only (%d owned)" % w.owned_count())
	_check(w.current_id == &"fiveseven", "default weapon is the suppressed Five-seveN")
	_check(not w.select(&"ak47"), "locked weapon cannot be selected")
	_check(w.grant(&"ak47"), "weapon pickup grants the AK-47")
	_check(w.select(&"ak47"), "granted weapon becomes selectable")
	_check(w.current_mode() == WeaponSystem.Mode.AUTO, "AK-47 defaults to AUTO")
	var shot: Dictionary = w.fire()
	_check(not shot.is_empty() and int(shot["ammo_left"]) == 29, "firing consumes a round")
	_check(w.fire().is_empty(), "fire cooldown blocks the next round")
	w.tick(0.13)
	_check(not w.fire().is_empty(), "auto interval allows the next round")
	_check(absf(float(shot["noise_radius"]) - 430.0) < 0.1, "AK-47 noise radius matches the web spec (430)")
	# burst mode
	var mp := WeaponSystem.new()
	mp.grant(&"mp5sd")
	mp.select(&"mp5sd")
	_check(mp.current_mode() == WeaponSystem.Mode.BURST, "MP5SD defaults to 3-burst")
	var fired: int = 0
	for i in range(3):
		if not mp.fire().is_empty():
			fired += 1
		mp.tick(0.09)
	_check(fired == 3, "burst fires exactly three rounds (%d)" % fired)
	_check(mp.fire().is_empty(), "burst recovery pauses after the burst")
	# reload
	var r := WeaponSystem.new()
	r.grant(&"hk416")
	r.select(&"hk416")
	for i in range(30):
		r.tick(0.25)
		r.fire()
	_check(r.magazine_empty(), "magazine empties after 30 rounds")
	_check(r.start_reload(), "reload starts when empty")
	_check(r.is_reloading(), "reload state is reported")
	r.tick(1.85)
	_check(int(r.state()["ammo"]) == 30, "reload refills the magazine")
	_check(int(r.state()["reserve"]) == 30, "reload draws from reserve")
	# melee + specs
	var k := WeaponSystem.new()
	k.select(&"knife")
	var kshot: Dictionary = k.fire()
	_check(bool(kshot["melee"]) and int(kshot["ammo_left"]) == 0, "knife is melee with no ammo")
	_check(absf(float(kshot["noise_radius"]) - 28.0) < 0.1, "knife is nearly silent (28)")
	_check(bool(WeaponSystem.SPECS[&"hk416"]["can_disable_cctv"]), "rifles can disable CCTV")
	_check(bool(WeaponSystem.SPECS[&"fiveseven"]["supports_emp"]), "Five-seveN supports EMP darts")
	_check(WeaponSystem.SPECS[&"p226"]["modes"].size() == 1, "P226 is semi only")
	_check(w.spread(true) < w.spread(false), "ADS spread is tighter than hip spread")
	_check(w.cycle_fire_mode() == WeaponSystem.Mode.SEMI, "fire mode cycles AUTO -> SEMI")
	_check(w.mode_label() == "SEMI" and w.mode_short_label() == "SEMI", "fire mode labels match the web HUD")
	var added: int = w.add_reserve(&"ak47")
	_check(added > 0, "ammo pickup adds reserve (%d)" % added)


func _cover() -> void:
	var c := CoverSystem.new()
	var walls := {Vector2i(0, 0): true, Vector2i(0, 1): true, Vector2i(0, 2): true}
	c.configure(walls, {}, 48.0, Vector3.ZERO)
	_check(c.anchor_count() > 0, "cover anchors are generated from walls (%d)" % c.anchor_count())
	var cell := Vector2i(1, 1)
	var pos: Vector3 = c.cell_to_world(cell)
	var threat: Vector3 = pos + Vector3(-200, 0, 0)
	_check(absf(c.cover_factor(pos, threat) - CoverSystem.WALL_COVER_FACTOR) < 0.001,
		"wall cover reduces visibility to 0.62")
	var open_pos: Vector3 = pos + Vector3(400, 0, 0)
	_check(absf(c.cover_factor(open_pos, threat) - 1.0) < 0.001, "open ground has no cover factor")
	var low := {cell: 46.0}
	var c2 := CoverSystem.new()
	c2.configure({}, low, 48.0, Vector3.ZERO)
	_check(absf(c2.cover_factor(pos, threat, true) - CoverSystem.LOW_COVER_FACTOR) < 0.001,
		"waist-high box hides a crouched actor")
	_check(absf(c2.cover_factor(pos, threat, false) - CoverSystem.LOW_COVER_FACTOR) < 0.001,
		"a 46-unit box also hides a standing actor")
	var spots: Array = c.cover_positions(pos, threat, 3)
	_check(spots.size() > 0, "cover positions behind walls are found (%d)" % spots.size())


func _cameras() -> void:
	var cam := SecurityCamera3D.new()
	var walls := {Vector2i(3, 1): true}
	cam.configure(walls, 48.0, Vector3.ZERO)
	cam.global_position = Vector3(48, 88, 48)
	cam.base_yaw = 0.0
	cam.sweep_arc = deg_to_rad(60.0)
	cam.sweep_speed = 0.8
	cam.view_range = 400.0
	cam.view_fov = deg_to_rad(60.0)
	var yaw0: float = cam.current_yaw
	cam.tick(0.6, Vector3(48, 0, 400))
	_check(absf(cam.current_yaw - yaw0) > 0.01, "camera sweeps over time")
	var target: Vector3 = cam.global_position + cam.facing() * 200.0
	target.y = 0.0
	_check(cam.can_see(target), "camera sees a target inside its cone")
	var behind: Vector3 = cam.global_position - cam.facing() * 200.0
	behind.y = 0.0
	_check(not cam.can_see(behind), "camera does not see behind itself")
	cam.set_disabled(true)
	_check(not cam.can_see(target) and not cam.is_spotting(), "EMP disables the camera")
	cam.set_disabled(false)
	_check(cam.can_see(target), "camera recovers when the EMP ends")


func _tripwires() -> void:
	var tw := LaserTripwire3D.new()
	tw.configure(Vector3(0, 30, 0), Vector3(96, 30, 0), 2.0, 2.0, 0.0)
	_check(tw.is_on_at(0.5), "tripwire is on early in its cycle")
	_check(not tw.is_on_at(2.5), "tripwire is off late in its cycle")
	_check(tw.is_on_at(4.5), "tripwire cycles back on")
	var hits: Array = []
	tw.tripped.connect(func(): hits.append(1))
	tw.tick(0.1, Vector3(48, 0, 0))
	_check(hits.size() == 1, "walking through a live beam trips it once")
	tw.tick(0.1, Vector3(48, 0, 0))
	_check(hits.size() == 1, "staying in the beam does not re-trip")
	tw.set_disabled(true)
	_check(not tw.is_on_at(0.5), "EMP disables the tripwire")


func _facility() -> void:
	var main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(main)
	for i in range(12):
		await physics_frame
	_check(main.weapons != null, "main3d owns a WeaponSystem")
	_check(main.cover != null, "main3d owns a CoverSystem")
	_check(main.security_cameras.size() > 0, "security cameras spawn (%d)" % main.security_cameras.size())
	_check(main.tripwires.size() > 0, "tripwires spawn (%d)" % main.tripwires.size())
	_check(main.facility_props.size() > 0, "procedural props spawn (%d)" % main.facility_props.size())
	_check(main.cover.anchor_count() > 0, "cover anchors follow the live layout")
	var before: int = main.level_data["gridmap_cells"]
	var shot: Dictionary = main.fire_weapon()
	_check(not shot.is_empty(), "fire_weapon returns a shot description")
	_check(main.weapons.shots_fired == 1, "shot counter advanced")
	var walkable_before: int = main.level_data["walkable_cells"]
	main.load_layout("layout_b")
	for i in range(8):
		await physics_frame
	_check(main.level_data["walkable_cells"] > 0, "layout reload keeps walkable cells")
	_check(main.security_cameras.size() > 0, "facility rebuilds on reload (%d cams)" % main.security_cameras.size())
	var cams: int = 0
	for child in main.get_children():
		if child is SecurityCamera3D:
			cams += 1
	_check(cams == main.security_cameras.size(), "no duplicate camera nodes after reload (%d)" % cams)
	_check(before > 0 and walkable_before > 0, "layout descriptors still report their counts")
	_check(main.level_root.detail != null, "detail GridMap still present")
