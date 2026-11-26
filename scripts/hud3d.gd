class_name Hud3D
extends Control
## Shadow Protocol - 3D HUD controller (Phase 3D-6).
##
## Reuses the SAME meter/overlay scripts the 2D prototype ships
## (visibility_meter, detection_meter, warning_layer, mission_overlay) so
## the presentation language stays identical, and drives them from live
## Main3D / Player3D / StealthSystem3D / MissionManager state.
##
## Adds the two 3D-specific pieces: a top-left mission status panel and a
## contextual interaction prompt ("USE: Open Door" / "USE: Hack Terminal").

const PROMPT_IDLE: String = ""
const RETICLE_IDLE: Color = Color(0.55, 0.90, 0.95, 0.55)
const RETICLE_TARGET: Color = Color(0.98, 0.72, 0.28, 0.95)

var main: Node = null
## Phase 3D-10 additions: weapon panel + SectorBlueprint, built in code so
## the existing hud3d.tscn node tree stays untouched.
var weapon_panel: PanelContainer = null
var weapon_name_label: Label = null
var weapon_ammo_label: Label = null
var weapon_mode_label: Label = null
var weapon_slots_label: Label = null
var blueprint: SectorBlueprint = null
var weapon_text: String = ""
var blueprint_cells: int = 0
## Phase 3D-11: health readout, hit direction and damage flash.
var health_label: Label = null
var hit_indicator: Control = null
var damage_flash: ColorRect = null
var hud_scale: float = 1.0
var health_text: String = ""
var last_hit_angle: float = 0.0
var hit_flash_left: float = 0.0

@onready var visibility_meter: Control = $VisibilityMeter
@onready var detection_meter: Control = $DetectionMeter
@onready var warning_layer: Control = $WarningLayer
@onready var mission_overlay: Control = $MissionOverlay
@onready var status_title: Label = $StatusPanel/Margin/Lines/Title
@onready var status_objectives: Label = $StatusPanel/Margin/Lines/Objectives
@onready var status_extraction: Label = $StatusPanel/Margin/Lines/Extraction
@onready var status_state: Label = $StatusPanel/Margin/Lines/State
@onready var prompt_label: Label = $InteractPrompt
@onready var reticle_dot: ColorRect = $Reticle/Dot

var objectives_done: int = 0
var objectives_total: int = 0
var extraction_available: bool = false
var prompt_text: String = ""
var last_visibility: float = 0.0
var last_detection_ratio: float = 0.0


## Binds the HUD to a live Main3D scene (safe to call again on restart).
func bind(scene: Node) -> void:
	main = scene
	if main == null:
		return
	if blueprint != null:
		blueprint.bind(main)
	if main.has_signal("hud_changed"):
		if not main.hud_changed.is_connected(refresh):
			main.hud_changed.connect(refresh)
	refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.text = PROMPT_IDLE
	reticle_dot.color = RETICLE_IDLE
	hud_scale = clampf(float(ProjectSettings.get_setting("shadow_protocol/hud_scale", 1.0)), 0.75, 1.6)
	_build_weapon_panel()
	_build_blueprint()
	_build_health()
	_build_damage_overlay()


func _build_weapon_panel() -> void:
	weapon_panel = PanelContainer.new()
	weapon_panel.name = "WeaponPanel"
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_panel.anchor_left = 0.0
	weapon_panel.anchor_top = 1.0
	weapon_panel.anchor_right = 0.0
	weapon_panel.anchor_bottom = 1.0
	weapon_panel.offset_left = 18.0 * hud_scale
	weapon_panel.offset_top = -108.0 * hud_scale
	weapon_panel.offset_right = 258.0 * hud_scale
	weapon_panel.offset_bottom = -18.0 * hud_scale
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	weapon_name_label = _mk_label(box, "WEAPON", int(15 * hud_scale), Palette.HUD_TEXT)
	weapon_ammo_label = _mk_label(box, "20 / 60", int(20 * hud_scale), Palette.INTERACTIVE)
	weapon_mode_label = _mk_label(box, "SEMI", int(13 * hud_scale), Palette.INTERACTIVE)
	weapon_slots_label = _mk_label(box, "1 2 3 4 5 6", int(12 * hud_scale), Palette.HUD_TEXT)
	weapon_panel.add_child(box)
	add_child(weapon_panel)


func _mk_label(parent: Node, text: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.modulate = color
	parent.add_child(l)
	return l


func _build_blueprint() -> void:
	blueprint = SectorBlueprint.new()
	blueprint.name = "SectorBlueprint"
	blueprint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blueprint.anchor_left = 1.0
	blueprint.anchor_top = 0.0
	blueprint.anchor_right = 1.0
	blueprint.anchor_bottom = 0.0
	blueprint.offset_left = -186.0 * hud_scale
	blueprint.offset_top = 18.0 * hud_scale
	blueprint.offset_right = -18.0 * hud_scale
	blueprint.offset_bottom = 186.0 * hud_scale
	add_child(blueprint)


func _process(_delta: float) -> void:
	refresh()


## Pulls the current state and repaints every HUD element.
func refresh() -> void:
	if main == null:
		return
	var mission: Node = main.get("mission")
	if mission != null:
		var player: Node = main.get("player")
		if player != null and "visibility" in player:
			last_visibility = float(player.visibility)
		visibility_meter.set_value(last_visibility)
		var grace: float = maxf(0.001, float(mission.detection_grace))
		last_detection_ratio = clampf(float(mission.detection_timer) / grace, 0.0, 1.0)
		detection_meter.set_value(last_detection_ratio)
		detection_meter.set_suspected(mission.state == MissionManager.State.ACTIVE and last_detection_ratio > 0.0)
		warning_layer.set_ratio(last_detection_ratio)
		var total: int = mission.objectives_total()
		var done: int = mission.objectives_done()
		objectives_done = done
		objectives_total = total
		extraction_available = mission.extraction_available()
		status_objectives.text = "OBJECTIVES %d/%d" % [done, total]
		status_extraction.text = "EXTRACTION READY" if extraction_available else "EXTRACTION LOCKED"
		status_extraction.modulate = Palette.EXTRACTION if extraction_available else Palette.EXTRACTION_LOCKED
		status_state.text = "STATE %s" % _state_name(int(mission.state))
		status_state.modulate = Palette.HUD_TEXT if mission.state == MissionManager.State.ACTIVE else Palette.INTERACTIVE
	_refresh_weapon()
	_refresh_health()
	prompt_text = main.interaction_hint() if main.has_method("interaction_hint") else PROMPT_IDLE
	prompt_label.text = prompt_text
	prompt_label.modulate = Palette.INTERACTIVE
	reticle_dot.color = RETICLE_TARGET if prompt_text != PROMPT_IDLE else RETICLE_IDLE


func _build_health() -> void:
	var panel := PanelContainer.new()
	panel.name = "HealthPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 18.0 * hud_scale
	panel.offset_top = (-108.0 - 46.0) * hud_scale
	panel.offset_right = 258.0 * hud_scale
	panel.offset_bottom = (-108.0 - 6.0) * hud_scale
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	health_label = _mk_label(box, "HP 100  ARM 40", int(16 * hud_scale), Palette.HUD_TEXT)
	panel.add_child(box)
	add_child(panel)


func _build_damage_overlay() -> void:
	damage_flash = ColorRect.new()
	damage_flash.name = "DamageFlash"
	damage_flash.color = Color(0.95, 0.15, 0.15, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(damage_flash)
	hit_indicator = Control.new()
	hit_indicator.name = "HitIndicator"
	hit_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_indicator.draw.connect(_draw_hit_indicator)
	add_child(hit_indicator)


## Shows where a hit came from, in screen space relative to the camera yaw.
func show_hit_direction(world_dir: Vector3) -> void:
	var yaw: float = 0.0
	if main != null and main.has_method("get") and main.get("player") != null:
		var rig: Node = main.player.get_node_or_null("CameraRig")
		if rig != null and "yaw" in rig:
			yaw = float(rig.yaw)
	var local: Vector3 = world_dir.rotated(Vector3.UP, -yaw)
	last_hit_angle = atan2(local.x, local.z)
	hit_flash_left = 0.9
	hit_indicator.queue_redraw()


func _draw_hit_indicator() -> void:
	if hit_flash_left <= 0.0:
		return
	var center := hit_indicator.size * 0.5
	var radius: float = minf(hit_indicator.size.x, hit_indicator.size.y) * 0.22
	var dir := Vector2(sin(last_hit_angle), -cos(last_hit_angle))
	var alpha: float = clampf(hit_flash_left / 0.9, 0.0, 1.0)
	var color := Color(1.0, 0.35, 0.3, 0.85 * alpha)
	var p1 := center + dir * radius
	var p2 := center + dir.rotated(0.16) * (radius + 26.0)
	var p3 := center + dir.rotated(-0.16) * (radius + 26.0)
	hit_indicator.draw_colored_polygon(PackedVector2Array([p1, p2, p3]), color)


## Live weapon readout: name/slot, magazine/reserve, fire mode, reload state
## and the owned-slot strip. Driven by the real WeaponSystem, never stubs.
func _refresh_weapon() -> void:
	if weapon_panel == null:
		return
	var weapons = main.get("weapons")
	if weapons == null:
		weapon_panel.visible = false
		return
	weapon_panel.visible = true
	var spec: Dictionary = weapons.spec()
	var st: Dictionary = weapons.state()
	var reloading: bool = weapons.is_reloading()
	weapon_name_label.text = "%d  %s" % [int(spec["slot"]), String(spec["short"])]
	weapon_ammo_label.text = "%d / %d" % [int(st["ammo"]), int(st["reserve"])]
	weapon_ammo_label.modulate = Palette.FAILURE if int(st["ammo"]) == 0 else Palette.INTERACTIVE
	if reloading:
		weapon_mode_label.text = "RELOADING"
		weapon_mode_label.modulate = Palette.FAILURE
	else:
		weapon_mode_label.text = weapons.mode_label()
		weapon_mode_label.modulate = Palette.INTERACTIVE
	var strip: String = ""
	for id: StringName in WeaponSystem.SLOT_IDS:
		var owned: bool = bool(weapons.state(id)["owned"])
		var slot: int = int(WeaponSystem.SPECS[id]["slot"])
		var mark: String = str(slot) if owned else "-"
		if id == weapons.current_id:
			mark = "[%s]" % mark
		strip += mark + " "
	weapon_slots_label.text = strip.strip_edges()
	weapon_text = "%s %s" % [weapon_name_label.text, weapon_ammo_label.text]
	blueprint_cells = blueprint.cells_drawn if blueprint != null else 0


## Health readout, damage flash decay and hit indicator fade.
func _refresh_health() -> void:
	if health_label == null:
		return
	var hp = main.get("health")
	if hp == null:
		health_label.text = "HP --"
		return
	health_label.text = "HP %d  ARM %d" % [int(round(float(hp.health))), int(round(float(hp.armor)))]
	health_label.modulate = Palette.FAILURE if hp.is_low() else Palette.HUD_TEXT
	health_text = health_label.text
	if damage_flash != null:
		var want: float = 0.0
		if not hp.alive:
			want = 0.35
		elif hit_flash_left > 0.0:
			want = 0.22 * clampf(hit_flash_left / 0.9, 0.0, 1.0)
		damage_flash.color.a = want
	if hit_flash_left > 0.0:
		hit_flash_left = maxf(0.0, hit_flash_left - get_process_delta_time())
		hit_indicator.queue_redraw()


## Hides the HUD (used while the mission overlay owns the screen).
func set_hud_visible(visible_now: bool) -> void:
	if weapon_panel != null:
		weapon_panel.visible = visible_now
	if blueprint != null:
		blueprint.visible = visible_now
	if hit_indicator != null:
		hit_indicator.visible = visible_now
	$StatusPanel.visible = visible_now
	visibility_meter.visible = visible_now
	detection_meter.visible = visible_now
	$Reticle.visible = visible_now
	prompt_label.visible = visible_now


func show_success(done: int, total: int) -> void:
	mission_overlay.show_success(done, total)


func show_failure(reason: String) -> void:
	mission_overlay.show_failure(reason)


func reset_overlay() -> void:
	mission_overlay.reset()


func _state_name(state: int) -> String:
	match state:
		MissionManager.State.READY:
			return "READY"
		MissionManager.State.ACTIVE:
			return "ACTIVE"
		MissionManager.State.SUCCEEDED:
			return "SUCCEEDED"
		MissionManager.State.FAILED:
			return "FAILED"
		_:
			return "?"
