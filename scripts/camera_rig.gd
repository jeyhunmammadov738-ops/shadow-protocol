extends Node3D
## Shadow Protocol - third-person camera rig (Phase 3D-1).
##
## Yaw lives on this node, pitch on the child SpringArm3D, so the camera
## orbits the player and never clips through geometry (the spring arm
## shortens on collision with world layer 1 and excludes the player body).
##
## Input rules (touch/mouse conflict resolution):
##   - Mobile: a touch may rotate the camera only when it is NOT owned by
##     the shared touch layer. The layer is the single source of truth:
##     joystick zone (left 45%) and the SPRINT/CROUCH/USE buttons always
##     win, so a button press can never spin the camera.
##   - Desktop: right-mouse drag.
## Rotation is clamped so the camera can never flip over the player.

const PITCH_MIN: float = -1.05   # ~-60 deg, looking down
const PITCH_MAX: float = 0.45    # ~+26 deg, looking up
const YAW_SENSITIVITY: float = 0.006
const PITCH_SENSITIVITY: float = 0.005
const TOUCH_YAW_SENSITIVITY: float = 0.008
const TOUCH_PITCH_SENSITIVITY: float = 0.008
const SPRING_LENGTH: float = 150.0
const SPRING_MARGIN: float = 8.0
const FALLBACK_RIGHT_ZONE_RATIO: float = 0.45

var yaw: float = 0.0
var pitch: float = -0.30

@export var touch_layer_path: NodePath = NodePath("../../UI/TouchLayer")

var _touch_layer: Control = null
var _touch_index: int = -1
var _last_touch_pos: Vector2 = Vector2.ZERO
var _mouse_dragging: bool = false

@onready var _spring: SpringArm3D = $SpringArm3D


func _ready() -> void:
	_touch_layer = get_node_or_null(touch_layer_path) as Control
	if _spring != null:
		_spring.spring_length = SPRING_LENGTH
		_spring.margin = SPRING_MARGIN
		_spring.collision_mask = 1
		var body := get_parent() as CollisionObject3D
		if body != null:
			_spring.add_excluded_object(body.get_rid())
	apply_rotation()


func get_yaw() -> float:
	return yaw


func get_pitch() -> float:
	return pitch


## Pushes the current yaw/pitch into the node transforms.
func apply_rotation() -> void:
	rotation.y = yaw
	if _spring != null:
		_spring.rotation.x = pitch


## Rotates the camera by the given deltas (radians) with pitch clamping.
func rotate_camera(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw - delta_yaw, -PI, PI)
	pitch = clampf(pitch - delta_pitch, PITCH_MIN, PITCH_MAX)
	apply_rotation()


## True when a touch at this position may start a camera drag: it must not
## belong to the touch layer's joystick zone or action buttons.
func accepts_touch(pos: Vector2) -> bool:
	if _touch_layer != null and is_instance_valid(_touch_layer) and _touch_layer.visible:
		if _touch_layer.has_method("is_position_owned"):
			return not _touch_layer.is_position_owned(pos)
		return pos.x > _viewport_width() * FALLBACK_RIGHT_ZONE_RATIO
	# No visible touch overlay (desktop): the whole screen is draggable.
	return true


func _viewport_width() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1280.0
	return vp.get_visible_rect().size.x


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and accepts_touch(event.position):
				_touch_index = event.index
				_last_touch_pos = event.position
		elif event.index == _touch_index:
			_touch_index = -1
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			var delta: Vector2 = event.position - _last_touch_pos
			_last_touch_pos = event.position
			rotate_camera(delta.x * TOUCH_YAW_SENSITIVITY, delta.y * TOUCH_PITCH_SENSITIVITY)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_dragging = event.pressed
	elif event is InputEventMouseMotion and _mouse_dragging:
		rotate_camera(event.relative.x * YAW_SENSITIVITY, event.relative.y * PITCH_SENSITIVITY)
