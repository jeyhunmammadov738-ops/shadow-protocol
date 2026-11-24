class_name LevelGenerator3D
extends Node3D
## Shadow Protocol - 3D level generation (Phase 3D-2).
##
## Maps the authoritative 2D grids from LevelCatalog 1:1 onto a GridMap of
## 48-unit cells (cell (gx, gy) -> GridMap cell (gx, 0, gy) -> world
## ((gx+0.5)*48, y, (gy+0.5)*48)). Layout data in level_catalog.gd stays
## read-only: this script only reads rows/zones and reports counts back so
## parity with the 2D layouts can be asserted by tests.

const CELL: float = 48.0
const WALL_HEIGHT: float = 92.0

const COLOR_TERMINAL := Color(0.98, 0.72, 0.28)
const COLOR_SPAWN := Color(0.45, 0.95, 1.0)
const COLOR_ENEMY := Color(0.95, 0.36, 0.30)
const COLOR_EXTRACTION := Color(0.35, 0.85, 0.45)
const COLOR_DOOR := Color(0.62, 0.70, 0.80)
const COLOR_ZONE := Color(0.90, 0.62, 0.20)

var grid_size: Vector2i = Vector2i.ZERO
var cell_size: float = CELL
var detail: GridMap = null
var origin: Vector3 = Vector3.ZERO
var bounds: AABB = AABB()
var wall_cells: Dictionary = {}
var lit_cells: Dictionary = {}
var door_cells: Dictionary = {}
var grid: GridMap = null


## Clears and rebuilds the level. Returns the data contract shared with the
## 2D generator (spawn/terminals/extraction/enemy_spawns/zones) plus the
## parity counts and the measured generation time.
func generate(rows: Array, zones: Array = []) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	_clear()
	var height: int = rows.size()
	var width: int = (rows[0] as String).length()
	for i in range(height):
		if (rows[i] as String).length() != width:
			push_error("level_generator_3d: ragged grid row %d" % i)
			width = maxi(width, (rows[i] as String).length())
	grid_size = Vector2i(width, height)
	bounds = AABB(Vector3.ZERO, Vector3(width * CELL, WALL_HEIGHT, height * CELL))

	# Pure character census: exactly one bucket per tile character, so the
	# counts compare 1:1 with an independent census of the 2D rows.
	var counts := {
		"floor_shadow": 0, "floor_lit": 0, "wall": 0, "terminal": 0,
		"spawn": 0, "enemy_spawn": 0, "extraction": 0, "door": 0,
	}
	var spawn_cell := Vector2i(-1, -1)
	var terminals: Array = []
	var enemy_spawns: Array = []
	var extraction := Vector3.ZERO
	var spawn := Vector3.ZERO

	grid = GridMap.new()
	grid.name = "GridMap"
	grid.mesh_library = GridCellLibrary.build()
	grid.cell_size = Vector3(CELL, CELL, CELL)
	# GridMap cell (gx, 0, gy) centres on y = CELL/2; shift the whole map so
	# the library's floor top (offset -FLOOR_THICKNESS/2) lands exactly on
	# y = 0 and wall bases sit on the floor plane.
	grid.position = Vector3(0.0, -CELL * 0.5, 0.0)
	grid.collision_layer = 1
	grid.collision_mask = 0
	add_child(grid)
	# Detail layer: grid seams on walkable cells, baseboard + cap on walls.
	# Same MeshLibrary, collision_layer 0, so it costs two draw calls and
	# never affects movement or line of sight.
	detail = GridMap.new()
	detail.name = "DetailGrid"
	detail.mesh_library = grid.mesh_library
	detail.cell_size = Vector3(CELL, CELL, CELL)
	detail.position = grid.position
	detail.collision_layer = 0
	detail.collision_mask = 0
	add_child(detail)

	for gy in range(height):
		var row: String = rows[gy]
		for gx in range(width):
			var tile: String = row[gx] if gx < row.length() else "2"
			var cell := Vector2i(gx, gy)
			var item: int = -1
			match tile:
				"0":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["floor_shadow"] += 1
				"1":
					item = GridCellLibrary.ITEM_FLOOR_LIT
					counts["floor_lit"] += 1
					lit_cells[cell] = true
				"2":
					item = GridCellLibrary.ITEM_WALL_A if (gx + gy) % 2 == 0 else GridCellLibrary.ITEM_WALL_B
					counts["wall"] += 1
					wall_cells[cell] = true
				"3":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["terminal"] += 1
					terminals.append(cell_to_world(cell))
					_add_plate(cell, 30.0, COLOR_TERMINAL, "Terminal")
				"4":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["spawn"] += 1
					spawn_cell = cell
					spawn = cell_to_world(cell)
					_add_plate(cell, 26.0, COLOR_SPAWN, "Spawn")
				"5":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["enemy_spawn"] += 1
					enemy_spawns.append(cell_to_world(cell))
					_add_plate(cell, 22.0, COLOR_ENEMY, "EnemySpawn")
				"6":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["extraction"] += 1
					extraction = cell_to_world(cell)
					_add_plate(cell, 34.0, COLOR_EXTRACTION, "Extraction")
				"7":
					item = GridCellLibrary.ITEM_FLOOR_SHADOW
					counts["door"] += 1
					door_cells[cell] = true
					_add_plate(cell, 40.0, COLOR_DOOR, "Door")
				_:
					push_error("level_generator_3d: unknown tile '%s' at %s" % [tile, cell])
					item = GridCellLibrary.ITEM_WALL_A
					counts["wall"] += 1
					wall_cells[cell] = true
			grid.set_cell_item(Vector3i(gx, 0, gy), item)
			var detail_item: int = -1
			if wall_cells.has(Vector2i(gx, gy)):
				detail_item = GridCellLibrary.ITEM_WALL_CAP
				detail.set_cell_item(Vector3i(gx, 0, gy), GridCellLibrary.ITEM_WALL_BASE)
			else:
				detail_item = GridCellLibrary.ITEM_FLOOR_SEAM
			if detail_item >= 0:
				detail.set_cell_item(Vector3i(gx, 0, gy), detail_item)

	for zone in zones:
		_add_zone_plate(zone)

	return {
		"spawn": spawn,
		"spawn_cell": spawn_cell,
		"wall_cells": wall_cells,
		"lit_cells": lit_cells,
		"door_cells": door_cells,
		"terminals": terminals,
		"extraction": extraction,
		"enemy_spawns": enemy_spawns,
		"zones": zones,
		"grid_size": grid_size,
		"cell_size": CELL,
		"origin": origin,
		"bounds": bounds,
		"counts": counts,
		"walkable_cells": counts["floor_shadow"] + counts["floor_lit"] + counts["terminal"] + counts["spawn"] + counts["enemy_spawn"] + counts["extraction"] + counts["door"],
		"gridmap_cells": grid.get_used_cells().size(),
		"generation_usec": Time.get_ticks_usec() - started,
	}


## Cell centre in world space (y = 1.0 so a spawned body settles onto the
## floor instead of starting exactly inside it).
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 1.0, (cell.y + 0.5) * CELL)


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / CELL)), int(floor(world_pos.z / CELL)))


func _add_plate(cell: Vector2i, size: float, color: Color, label: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, 0.8, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	mesh.material = mat
	var plate := MeshInstance3D.new()
	plate.name = label + "%d_%d" % [cell.x, cell.y]
	plate.mesh = mesh
	plate.position = cell_to_world(cell) + Vector3(0.0, 0.4, 0.0)
	add_child(plate)


func _add_zone_plate(zone: Dictionary) -> void:
	var rect: Rect2i = zone["rect"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x * CELL, 0.4, rect.size.y * CELL)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(COLOR_ZONE.r, COLOR_ZONE.g, COLOR_ZONE.b, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var plate := MeshInstance3D.new()
	plate.name = "Zone_%s" % str(zone.get("id", "zone"))
	plate.mesh = mesh
	plate.position = Vector3(
		(rect.position.x + rect.size.x * 0.5) * CELL, 0.2,
		(rect.position.y + rect.size.y * 0.5) * CELL)
	add_child(plate)


func _clear() -> void:
	if detail != null and is_instance_valid(detail):
		detail.queue_free()
	detail = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	grid = null
	wall_cells = {}
	lit_cells = {}
	door_cells = {}
