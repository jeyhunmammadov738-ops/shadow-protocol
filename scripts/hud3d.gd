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
	if main.has_signal("hud_changed"):
		if not main.hud_changed.is_connected(refresh):
			main.hud_changed.connect(refresh)
	refresh()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.text = PROMPT_IDLE
	reticle_dot.color = RETICLE_IDLE


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
	prompt_text = main.interaction_hint() if main.has_method("interaction_hint") else PROMPT_IDLE
	prompt_label.text = prompt_text
	prompt_label.modulate = Palette.INTERACTIVE
	reticle_dot.color = RETICLE_TARGET if prompt_text != PROMPT_IDLE else RETICLE_IDLE


## Hides the HUD (used while the mission overlay owns the screen).
func set_hud_visible(visible_now: bool) -> void:
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
