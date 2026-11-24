extends SceneTree
## Phase 3D-8: visual quality, TPS camera overhaul and movement feel.

var _checks: int = 0
var _fails: int = 0
var _main: Node3D = null
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


func _run() -> void:
	print("3D PHASE-8 TEST: starting")
	_main = load("res://scenes/main3d.tscn").instantiate()
	root.add_child(_main)
	await _frames(20)
	_player = _main.player
	var rig = _player.get_node("CameraRig")

	# --- tactical wall height --------------------------------------------
	_check(GridCellLibrary.WALL_HEIGHT == 92.0, "wall height is tactical 92 units (was 120)")
	_check(_main.level_root.bounds.size.y == 92.0, "level bounds follow the new wall height")

	# --- procedural character rigs ---------------------------------------
	var prig = _player.rig
	_check(prig != null, "player uses a procedural character rig")
	_check(prig.parts.size() >= 14, "player rig is multi-part (%d meshes)" % prig.parts.size())
	_check(prig.legs.size() == 2 and prig.arms.size() == 2, "player rig has articulated legs and arms")
	var player_emissive: int = 0
	for mi in prig.parts:
		if mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).emission_enabled:
			player_emissive += 1
	_check(player_emissive >= 3, "player has glowing tri-focal visor lenses (%d emissive parts)" % player_emissive)
	var guard = _main.enemies()[0]
	_check(guard.rig != null, "guards use a procedural rig")
	_check(guard.rig.parts.size() >= 14, "guard rig is multi-part (%d meshes)" % guard.rig.parts.size())
	_check(guard.rig.kind == "guard", "guard rig uses the armoured variant")

	# --- stride animation -------------------------------------------------
	var before: float = prig.legs[0].rotation.x
	_player.use_input_override = true
	_player.input_override = Vector2(0.0, -1.0)
	await _frames(24)
	var after: float = prig.legs[0].rotation.x
	_check(absf(after - before) > 0.05, "walking animates the leg stride (%.2f -> %.2f)" % [before, after])
	_player.input_override = Vector2.ZERO
	await _frames(6)

	# --- camera overhaul ---------------------------------------------------
	_check(absf(rig._spring.margin - 4.0) < 0.01, "spring arm uses a tight 4-unit margin")
	var yaw_target: float = rig.yaw + 1.2
	rig.yaw = yaw_target
	await _frames(2)
	var mid: float = rig.rotation.y
	_check(absf(mid - yaw_target) > 0.05, "yaw is damped, not snapped (mid %.2f of %.2f)" % [mid, yaw_target])
	await _frames(40)
	_check(absf(rig.rotation.y - yaw_target) < 0.08, "damped yaw converges on the target")
	_check(rig.is_framing_tight() == false, "camera keeps a usable distance in the corridor")
	var fov_before: float = rig._fov
	if _player.has_method("set_touch_sprint"):
		_player.set_touch_sprint(true)
	_player.sprinting = true
	_player.input_override = Vector2(0.0, -1.0)
	await _frames(40)
	_check(rig._fov > fov_before + 2.0, "sprint widens the FOV (%.1f -> %.1f)" % [fov_before, rig._fov])
	_player.sprinting = false
	if _player.has_method("set_touch_sprint"):
		_player.set_touch_sprint(false)
	_player.input_override = Vector2.ZERO
	await _frames(30)
	_check(rig._fov < 74.0, "FOV settles back after sprinting")

	# --- tactical environment ---------------------------------------------
	var detail: GridMap = _main.level_root.detail
	_check(detail != null, "detail GridMap layer exists")
	_check(detail.get_used_cells().size() > 0, "detail layer populates the level (%d cells)" % detail.get_used_cells().size())
	_check(detail.collision_layer == 0, "detail layer is collision-free")
	var caps: int = 0
	var seams: int = 0
	for c in detail.get_used_cells():
		var item: int = detail.get_cell_item(c)
		if item == GridCellLibrary.ITEM_WALL_CAP:
			caps += 1
		elif item == GridCellLibrary.ITEM_FLOOR_SEAM:
			seams += 1
	_check(caps > 0 and seams > 0, "walls get top caps (%d) and floors get grid seams (%d)" % [caps, seams])
	var floor_mesh := _main.level_root.grid.mesh_library.get_item_mesh(GridCellLibrary.ITEM_FLOOR_SHADOW) as BoxMesh
	var floor_mat := floor_mesh.material as StandardMaterial3D
	_check(floor_mat.albedo_color.get_luminance() > 0.04,
		"floor is a readable slate instead of pitch black (%.3f)" % floor_mat.albedo_color.get_luminance())

	# --- draw discipline --------------------------------------------------
	var grids: int = 0
	var meshes: int = 0
	var stack: Array = [_main]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is GridMap:
			grids += 1
		elif n is MeshInstance3D:
			meshes += 1
		stack.append_array(n.get_children())
	_check(grids == 2, "level renders through two GridMaps (%d)" % grids)
	_check(meshes < 300, "mesh instances stay within the mobile budget (%d < 300)" % meshes)

	# --- restart cleanliness ----------------------------------------------
	for key in ["layout_b", "layout_c", "legacy"]:
		_main.load_layout(key)
		await _frames(8)
	var g2: int = 0
	var st: Array = [_main]
	while st.size() > 0:
		var n: Node = st.pop_back()
		if n is GridMap:
			g2 += 1
		st.append_array(n.get_children())
	_check(g2 == 2, "restarts keep exactly two GridMaps (%d)" % g2)
	_check(_main.level_root.detail != null, "detail layer is rebuilt on restart")

	print("3D PHASE-8 TEST: %d PASS / %d FAIL" % [_checks - _fails, _fails])
	if _fails > 0:
		print("3D PHASE-8 TEST: FAILURES PRESENT")
		quit(1)
	else:
		print("3D PHASE-8 TEST: all checks passed")
		quit(0)
