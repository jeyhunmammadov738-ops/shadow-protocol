class_name GridCellLibrary
## Shadow Protocol - procedural 3D cell library (Phase 3D-2).
##
## One BoxMesh item per authoritative 48-unit tile character defined in
## LevelCatalog (see its CENTRAL TILE ENCODING). Built once, shared by
## every GridMap; no external meshes, textures or art assets are used.

const CELL: float = 48.0
const WALL_HEIGHT: float = 120.0
const FLOOR_THICKNESS: float = 8.0

const ITEM_FLOOR_SHADOW: int = 0
const ITEM_FLOOR_LIT: int = 1
const ITEM_WALL_A: int = 2
const ITEM_WALL_B: int = 3

static var _shared: MeshLibrary = null


## Builds (once) and returns the shared MeshLibrary.
static func build() -> MeshLibrary:
	if _shared != null:
		return _shared
	var lib := MeshLibrary.new()
	lib.create_item(ITEM_FLOOR_SHADOW)
	lib.set_item_name(ITEM_FLOOR_SHADOW, "floor_shadow")
	_configure_floor(lib, ITEM_FLOOR_SHADOW, Palette.FLOOR, Color(0, 0, 0), 0.0)
	lib.create_item(ITEM_FLOOR_LIT)
	lib.set_item_name(ITEM_FLOOR_LIT, "floor_lit")
	_configure_floor(lib, ITEM_FLOOR_LIT, Palette.FLOOR.lerp(Palette.FLOOR_LIT, 0.75), Palette.FLOOR_LIT, 0.55)
	lib.create_item(ITEM_WALL_A)
	lib.set_item_name(ITEM_WALL_A, "wall_a")
	_configure_wall(lib, ITEM_WALL_A, Palette.WALL, Palette.WALL_TOP)
	lib.create_item(ITEM_WALL_B)
	lib.set_item_name(ITEM_WALL_B, "wall_b")
	_configure_wall(lib, ITEM_WALL_B, Palette.WALL.lightened(0.08), Palette.WALL_TOP.lightened(0.05))
	_shared = lib
	return lib


static func _configure_floor(lib: MeshLibrary, id: int, albedo: Color,
		emission: Color, energy: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL, FLOOR_THICKNESS, CELL)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = 0.85
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = energy
	mesh.material = mat
	lib.set_item_mesh(id, mesh)
	# Top face sits exactly at y = 0 so the 48-unit grid maps 1:1.
	var offset := Transform3D(Basis(), Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0))
	lib.set_item_mesh_transform(id, offset)
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, FLOOR_THICKNESS, CELL)
	lib.set_item_shapes(id, [shape, offset])


static func _configure_wall(lib: MeshLibrary, id: int, albedo: Color,
		trim: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL, WALL_HEIGHT, CELL)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = 0.9
	mesh.material = mat
	lib.set_item_mesh(id, mesh)
	var offset := Transform3D(Basis(), Vector3(0.0, WALL_HEIGHT * 0.5, 0.0))
	lib.set_item_mesh_transform(id, offset)
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, WALL_HEIGHT, CELL)
	lib.set_item_shapes(id, [shape, offset])
	# Subtle trim emission keeps wall faces readable in dark corridors.
	mat.emission_enabled = true
	mat.emission = trim
	mat.emission_energy_multiplier = 0.08
