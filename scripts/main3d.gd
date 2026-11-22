extends Node3D
## Shadow Protocol - Phase 3D-1 scene wiring (main3d.tscn).
##
## Kept fully separate from the 2D prototype: main.tscn and its scripts
## are untouched. This scene only connects the shared touch overlay
## (scripts/mobile_controls.gd) to the 3D player and exposes a small
## debug readout while the 3D skeleton is under construction.

@onready var player: CharacterBody3D = $Player3D
@onready var touch_layer: Control = $UI/TouchLayer
@onready var _hud: Label = $UI/HUD


func _ready() -> void:
	if player != null and player.has_method("set_touch_controls"):
		player.set_touch_controls(touch_layer)
	if touch_layer != null and player != null:
		touch_layer.crouch_toggled.connect(player.set_touch_crouch)
		touch_layer.sprint_toggled.connect(player.set_touch_sprint)
		# INTERACT has no 3D target until Phase 3D-5 (terminals/doors).


func _process(_delta: float) -> void:
	if _hud == null or player == null:
		return
	var rig := player.get_node_or_null("CameraRig")
	var yaw_text: String = "0"
	if rig != null and rig.has_method("get_yaw"):
		yaw_text = str(snappedf(rad_to_deg(rig.get_yaw()), 1.0))
	_hud.text = "3D SKELETON  |  FPS %d  |  yaw %s°  |  crouch %s  sprint %s" % [
		Engine.get_frames_per_second(),
		yaw_text,
		"ON" if player.crouching else "off",
		"ON" if player.sprinting else "off",
	]
