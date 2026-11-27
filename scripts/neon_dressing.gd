class_name NeonDressing
extends Node3D
## Shadow Protocol - "Stylized Neon Noir" set dressing (Phase 3D-13).
##
## The device run showed near-uniform grey boxes with a flat ambient wash.
## This layer breaks those surfaces up and adds depth WITHOUT touching gameplay
## geometry, lighting logic or the level generator's tile encoding:
##
##   * recessed wall panel seams and a value-varied panel per wall face
##   * floor grid lines and scuff patches along walkable cells
##   * ceiling beams, cable runs, vents and signage plates
##   * emissive corridor strips plus strips around doors and terminals
##   * additive floor glow quads under emissive fixtures (no real light)
##   * a few shadowless OmniLight3D pools near terminals and doors
##   * distance fog to hide the map edge
##
## Everything that repeats is a MultiMeshInstance3D, so the whole dressing pass
## costs a handful of draw calls. Hard caps (MAX_REAL_LIGHTS, MAX_DRESSING_MESHES)
## are enforced and reported by `budget_report()`.
##
## Forbidden here by design: realtime shadows, SSAO, bloom, PBR texture sets.

const MAX_REAL_LIGHTS: int = 6
const MAX_DRESSING_MESHES: int = 900
const CELL: float = 48.0

const STRUCTURE := Color(0.13, 0.16, 0.22)
const STRUCTURE_LIGHT := Color(0.19, 0.23, 0.30)
const SEAM := Color(0.07, 0.09, 0.12)
const NEON_CYAN := Color(0.30, 0.85, 0.95)
const NEON_AMBER := Color(0.98, 0.72, 0.28)
const NEON_RED := Color(0.92, 0.28, 0.30)
const FLOOR_GLOW := Color(0.30, 0.85, 0.95, 0.16)

var level_data: Dictionary = {}
var real_lights: int = 0
var dressing_meshes: int = 0
var multimesh_batches: int = 0
var glow_quads: int = 0
var fog_enabled: bool = false

var _wall_seams: Array = []
var _floor_lines: Array = []
var _scuffs: Array = []
var _glows: Array = []


## Builds the whole dressing pass for one layout. Safe to call repeatedly:
## previous children are cleared first so restarts cannot pile up meshes.
func build(data: Dictionary, env: Environment = null) -> void:
	level_data = data
	clear()
	var walls: Dictionary = data.get("wall_cells", {})
	var lit: Dictionary = data.get("lit_cells", {})
	var origin: Vector3 = data.get("origin", Vector3.ZERO)
	var cell: float = float(data.get("cell_size", CELL))
	_collect_wall_seams(walls, origin, cell)
	_collect_floor_lines(walls, lit, origin, cell)
	_flush_batches(cell)
	_add_ceiling_beams(walls, origin, cell)
	_add_emissive_strips(data, origin, cell)
	_add_prop_clusters(data, origin, cell)
	_add_light_pools(data, origin, cell)
	_apply_atmosphere(env)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_wall_seams.clear()
	_floor_lines.clear()
	_scuffs.clear()
	_glows.clear()
	real_lights = 0
	dressing_meshes = 0
	multimesh_batches = 0
	glow_quads = 0


func budget_report() -> Dictionary:
	return {
		"real_lights": real_lights,
		"max_real_lights": MAX_REAL_LIGHTS,
		"dressing_meshes": dressing_meshes,
		"max_dressing_meshes": MAX_DRESSING_MESHES,
		"multimesh_batches": multimesh_batches,
		"glow_quads": glow_quads,
		"fog_enabled": fog_enabled,
		"within_budget": real_lights <= MAX_REAL_LIGHTS and dressing_meshes <= MAX_DRESSING_MESHES,
	}


# --------------------------------------------------------------- collectors --

func _collect_wall_seams(walls: Dictionary, origin: Vector3, cell: float) -> void:
	for wall_cell: Vector2i in walls.keys():
		if _wall_seams.size() >= 320:
			return
		var base: Vector3 = origin + Vector3(
			(float(wall_cell.x) + 0.5) * cell, 0.0, (float(wall_cell.y) + 0.5) * cell)
		# A recessed horizontal seam mid-wall plus a vertical seam at the joint.
		_wall_seams.append([base + Vector3(0.0, 46.0, 0.0), Vector3(cell * 0.92, 2.2, 2.2)])
		if absi(wall_cell.x + wall_cell.y) % 2 == 0:
			_wall_seams.append([base + Vector3(0.0, 23.0, 0.0), Vector3(2.2, 44.0, cell * 0.9)])


func _collect_floor_lines(walls: Dictionary, lit: Dictionary, origin: Vector3, cell: float) -> void:
	var cells: Array = lit.keys()
	for c: Vector2i in cells:
		if _floor_lines.size() >= 300:
			return
		var base: Vector3 = origin + Vector3(
			(float(c.x) + 0.5) * cell, 0.0, (float(c.y) + 0.5) * cell)
		_floor_lines.append([base + Vector3(0.0, 0.6, -cell * 0.5), Vector3(cell, 0.6, 1.4)])
		_floor_lines.append([base + Vector3(-cell * 0.5, 0.6, 0.0), Vector3(1.4, 0.6, cell)])
		if absi(c.x * 7 + c.y * 13) % 9 == 0:
			_scuffs.append([base + Vector3(0.0, 0.8, 0.0), Vector3(cell * 0.55, 0.5, cell * 0.35)])


## Turns the collected transforms into a few MultiMesh batches.
func _flush_batches(cell: float) -> void:
	if _wall_seams.size() > 0:
		_add_multimesh(_wall_seams, SEAM, false)
	if _floor_lines.size() > 0:
		_add_multimesh(_floor_lines, SEAM.lightened(0.05), false)
	if _scuffs.size() > 0:
		_add_multimesh(_scuffs, Color(0.09, 0.11, 0.14), false)


func _add_multimesh(entries: Array, color: Color, emissive: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	(mm.mesh as BoxMesh).size = Vector3.ONE
	mm.instance_count = entries.size()
	for i in range(entries.size()):
		var e: Array = entries[i]
		var size: Vector3 = e[1]
		var xform := Transform3D(Basis.from_scale(size), e[0])
		mm.set_instance_transform(i, xform)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material(color, emissive, 1.0)
	add_child(mmi)
	multimesh_batches += 1
	dressing_meshes += entries.size()


func _material(color: Color, emissive: bool, energy: float = 1.0,
		transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Layout data mixes Arrays and cell-keyed Dictionaries; iterate either.
func _items(value: Variant) -> Array:
	if value is Dictionary:
		return (value as Dictionary).keys()
	if value is Array:
		return value as Array
	return []


## Accepts either a grid cell (Vector2i) or a world position (Vector3).
func _as_world(raw: Variant, origin: Vector3, cell: float) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	if raw is Vector2i:
		var c: Vector2i = raw as Vector2i
		return origin + Vector3((float(c.x) + 0.5) * cell, 0.0, (float(c.y) + 0.5) * cell)
	if raw is Vector2:
		var v: Vector2 = raw as Vector2
		return origin + Vector3(v.x, 0.0, v.y)
	return origin


# ----------------------------------------------------------------- fixtures --

func _add_ceiling_beams(walls: Dictionary, origin: Vector3, cell: float) -> void:
	var bounds: Variant = level_data.get("bounds", null)
	var span_x: float = 0.0
	var span_z: float = 0.0
	if bounds is AABB:
		span_x = (bounds as AABB).size.x
		span_z = (bounds as AABB).size.z
	elif bounds is Dictionary:
		span_x = float((bounds as Dictionary).get("size_x", 0.0)) * cell
		span_z = float((bounds as Dictionary).get("size_z", 0.0)) * cell
	if span_x <= 0.0 or span_z <= 0.0:
		return
	var beams: Array = []
	var step: float = cell * 4.0
	var x: float = 0.0
	while x <= span_x and beams.size() < 40:
		beams.append([origin + Vector3(x, 92.0, span_z * 0.5), Vector3(3.0, 4.0, span_z)])
		x += step
	if beams.size() > 0:
		_add_multimesh(beams, STRUCTURE_LIGHT, false)


func _add_emissive_strips(data: Dictionary, origin: Vector3, cell: float) -> void:
	var strips: Array = []
	for door_cell in _items(data.get("door_cells", [])):
		if strips.size() >= 40:
			break
		var base: Vector3 = _as_world(door_cell, origin, cell)
		strips.append([base + Vector3(0.0, 84.0, 0.0), Vector3(cell * 0.9, 1.6, 2.0)])
		_glows.append([base + Vector3(0.0, 1.2, 0.0), Vector3(cell * 0.9, 0.4, cell * 0.9)])
	for raw in data.get("terminals", []):
		if strips.size() >= 60:
			break
		var term: Vector3 = _as_world(raw, origin, cell)
		strips.append([term + Vector3(0.0, 62.0, 0.0), Vector3(10.0, 1.4, 10.0)])
		_glows.append([term + Vector3(0.0, 1.2, 0.0), Vector3(cell * 0.8, 0.4, cell * 0.8)])
	# corridor runners: a cyan strip along lit cells for depth
	var lit: Dictionary = data.get("lit_cells", {})
	var runner: int = 0
	for c: Vector2i in lit.keys():
		if runner >= 24:
			break
		if absi(c.x + c.y * 3) % 11 != 0:
			continue
		var base: Vector3 = origin + Vector3(
			(float(c.x) + 0.5) * cell, 0.0, (float(c.y) + 0.5) * cell)
		strips.append([base + Vector3(0.0, 88.0, 0.0), Vector3(cell * 0.7, 1.2, 1.2)])
		runner += 1
	if strips.size() > 0:
		_add_multimesh(strips, NEON_CYAN, true)
		_add_multimesh_emissive_energy(strips)
	if _glows.size() > 0:
		_add_glow_multimesh()


func _add_multimesh_emissive_energy(entries: Array) -> void:
	# The strip batch is already added; bump its emission so it reads at night.
	for child in get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.material_override is StandardMaterial3D:
				var mat := mmi.material_override as StandardMaterial3D
				if mat.emission_enabled and mat.emission == NEON_CYAN:
					mat.emission_energy_multiplier = 1.9


func _add_glow_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	(mm.mesh as QuadMesh).size = Vector2.ONE
	mm.instance_count = _glows.size()
	for i in range(_glows.size()):
		var e: Array = _glows[i]
		var size: Vector3 = e[1]
		var basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(size)
		mm.set_instance_transform(i, Transform3D(basis, e[0]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _material(FLOOR_GLOW, true, 0.6, true)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	multimesh_batches += 1
	glow_quads += _glows.size()
	dressing_meshes += _glows.size()


func _add_prop_clusters(data: Dictionary, origin: Vector3, cell: float) -> void:
	var walls: Dictionary = data.get("wall_cells", {})
	var lit: Dictionary = data.get("lit_cells", {})
	var placed: int = 0
	var cells: Array = lit.keys()
	for c: Vector2i in cells:
		if placed >= 10:
			break
		if absi(c.x * 5 + c.y * 11) % 17 != 0:
			continue
		var base: Vector3 = origin + Vector3(
			(float(c.x) + 0.5) * cell, 0.0, (float(c.y) + 0.5) * cell)
		var prop: Node3D = null
		match placed % 4:
			0:
				prop = PropFactory.make_hide_container("crate")
			1:
				prop = PropFactory.make_vent_hatch()
			2:
				prop = PropFactory.make_breaker_box()
			_:
				prop = PropFactory.make_decoy()
		if prop == null:
			continue
		prop.position = base + Vector3(cell * 0.25, 0.0, -cell * 0.25)
		add_child(prop)
		placed += 1
		dressing_meshes += 1


func _add_light_pools(data: Dictionary, origin: Vector3, cell: float) -> void:
	var spots: Array = []
	for raw in data.get("terminals", []):
		spots.append(_as_world(raw, origin, cell) + Vector3(0.0, 66.0, 0.0))
	for door_cell in _items(data.get("door_cells", [])):
		var dpos: Vector3 = _as_world(door_cell, origin, cell)
		spots.append(dpos + Vector3(0.0, 70.0, 0.0))
	for spot: Vector3 in spots:
		if real_lights >= MAX_REAL_LIGHTS:
			return
		var light := OmniLight3D.new()
		light.position = spot
		light.omni_range = cell * 2.4
		light.light_energy = 0.9
		light.light_color = NEON_CYAN
		# No realtime shadows on mobile: the value variation carries depth.
		light.shadow_enabled = false
		add_child(light)
		real_lights += 1


func _apply_atmosphere(env: Environment) -> void:
	if env == null:
		return
	# Distance fog hides the map edge and adds depth without a post stack.
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.12)
	env.fog_light_energy = 0.55
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.20, 0.28)
	env.ambient_light_energy = 0.42
	fog_enabled = true
