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

## 3D-13 framing: the device run showed a large empty dark band across the
## top third (camera too low and level, pointing at the void). The rig is now
## a shoulder TPS: head-height pivot, ~4.6 m back (project scale: the player
## rig is 90 units tall, so 1 unit = 2 cm and 4-5 "units" = 200-250 world
## units), a wide shoulder offset and a slight downward pitch so floor and
## corridor dominate the frame.
const PITCH_MIN: float = -0.96   # ~-55 deg, looking down
const PITCH_MAX: float = 0.61    # ~+35 deg, looking up
const YAW_SENSITIVITY: float = 0.006
const PITCH_SENSITIVITY: float = 0.005
const TOUCH_YAW_SENSITIVITY: float = 0.008
const TOUCH_PITCH_SENSITIVITY: float = 0.008
const SPRING_LENGTH: float = 230.0
const SHOULDER_OFFSET: float = 40.0
const MIN_CAM_DISTANCE: float = 90.0
const YAW_DAMPING: float = 14.0
const PITCH_DAMPING: float = 12.0
const FOV_BASE: float = 68.0
const FOV_SPRINT: float = 77.0
const FOV_DAMPING: float = 5.0
## 3D-13: with the longer shoulder arm the old lift (-0.95 rad, triggered at
## 90% compression) fired constantly inside 48-unit corridors and pointed the
## camera at the floor - the "empty frame" the owner saw. The lift is now a
## gentle climb that only triggers when the arm is genuinely buried.
## Steep enough to clear a 92-unit wall that sits 27 units behind the pivot
## (atan(20/27) = 37 deg is the minimum; 54 deg clears it with margin).
const BLOCKED_PITCH: float = -0.95
const BLOCKED_RATIO: float = 0.45
## 3D-10: the lift-over used to oscillate at wall edges (blocked -> lift ->
## clear -> lower -> blocked), which pumped the camera and made the framing
## test flaky. The lift is now latched until the player actually moves away
## or turns, which is also how a hand-animated camera behaves.
const LIFT_RESET_DISTANCE: float = 48.0
const LIFT_RESET_YAW: float = 0.35
const SPRING_MARGIN: float = 8.0
const FALLBACK_RIGHT_ZONE_RATIO: float = 0.45

var yaw: float = 0.0
var pitch: float = -0.30
## Effective pitch actually applied: rises toward BLOCKED_PITCH when the
## spring arm is compressed, so a wall behind the player never leaves a
## collapsed, unusable view (device report: spawn camera against a wall).
var _effective_pitch: float = -0.30
var _yaw_smooth: float = 0.0
var _pitch_smooth: float = -0.30
var _fov: float = 68.0

@export var touch_layer_path: NodePath = NodePath("../../UI/TouchLayer")
## Look sensitivity multiplier (settings-ready; 1.0 = tuned default).
@export_range(0.3, 2.5, 0.05) var look_sensitivity: float = 1.0
## Drags shorter than this are ignored so a resting thumb cannot spin the view.
const TOUCH_DRAG_DEADZONE: float = 2.0

var _touch_layer: Control = null
var _touch_index: int = -1
var _last_touch_pos: Vector2 = Vector2.ZERO
var _mouse_dragging: bool = false
var _target_sprinting: bool = false

@onready var _spring: SpringArm3D = $SpringArm3D
var _excluded: Dictionary = {}
var _lift_active: bool = false
var _lift_pos: Vector3 = Vector3.ZERO
var _lift_yaw: float = 0.0


## Keeps a physics body out of the camera's spring collision set.
func exclude_body(body: Node) -> void:
	if body == null or not (body is CollisionObject3D):
		return
	if _spring == null:
		return
	var rid: RID = body.get_rid()
	if _excluded.has(rid):
		return
	_excluded[rid] = true
	_spring.add_excluded_object(rid)


func _ready() -> void:
	_touch_layer = get_node_or_null(touch_layer_path) as Control
	if _spring != null:
		_spring.spring_length = SPRING_LENGTH
		# Tighter margin keeps the camera off walls without a visible pop.
		_spring.margin = 4.0
		_spring.collision_mask = 1
		# 3D-10: actors share layer 1 with the world, so a guard walking
		# behind the player used to compress the spring arm. Exclude actor
		# bodies explicitly; walls and props still block the camera.
		_excluded.clear()
		var body := get_parent() as CollisionObject3D
		if body != null:
			_spring.add_excluded_object(body.get_rid())
	# Over-the-shoulder framing. The lateral offset lives on the ARM, not on
	# the camera child: SpringArm3D rewrites its child's position every frame,
	# so the old `cam.position.x` assignment was silently discarded (found in
	# 3D-13 - the "shoulder" camera had always been dead centre).
	_spring.position = Vector3(SHOULDER_OFFSET, 0.0, 0.0)
	apply_rotation()


## Lateral shoulder offset actually applied to the arm (tests, settings).
func shoulder_offset() -> float:
	if _spring == null:
		return 0.0
	return _spring.position.x


## Sprint drives the subtle FOV widen.
func set_sprinting(active: bool) -> void:
	_target_sprinting = active


## True when the arm is so compressed the camera would sit in the head.
func is_framing_tight() -> bool:
	if _spring == null:
		return false
	return _spring.get_hit_length() < MIN_CAM_DISTANCE


func get_yaw() -> float:
	return yaw


func get_pitch() -> float:
	return pitch


## Pushes the current yaw/pitch into the node transforms.
## Lifts the camera over obstruction instead of only shortening the arm.
func _process(delta: float) -> void:
	if _spring == null:
		return
	var hit: float = _spring.get_hit_length()
	if not _lift_active:
		if hit < SPRING_LENGTH * BLOCKED_RATIO:
			_lift_active = true
			_lift_pos = global_position
			_lift_yaw = yaw
	elif global_position.distance_to(_lift_pos) > LIFT_RESET_DISTANCE \
			or absf(angle_difference(_lift_yaw, yaw)) > LIFT_RESET_YAW:
		_lift_active = false
	var target: float = BLOCKED_PITCH if _lift_active else pitch
	_effective_pitch = lerpf(_effective_pitch, target, minf(1.0, 8.0 * delta))
	# Damped yaw/pitch: steering feels fluid instead of snapping.
	_yaw_smooth = lerp_angle(_yaw_smooth, yaw, minf(1.0, YAW_DAMPING * delta))
	_pitch_smooth = lerpf(_pitch_smooth, _effective_pitch, minf(1.0, PITCH_DAMPING * delta))
	rotation.y = _yaw_smooth
	_spring.rotation.x = _pitch_smooth
	# Subtle speed FOV so movement reads clearly without a dolly zoom.
	var want_fov: float = FOV_SPRINT if _target_sprinting else FOV_BASE
	_fov = lerpf(_fov, want_fov, minf(1.0, FOV_DAMPING * delta))
	var cam := _spring.get_node_or_null("Camera3D") as Camera3D
	if cam != null and absf(cam.fov - _fov) > 0.01:
		cam.fov = _fov


func apply_rotation() -> void:
	rotation.y = yaw
	if _spring != null:
		_effective_pitch = pitch
		_spring.rotation.x = pitch


## Rotates the camera by the given deltas (radians) with pitch clamping.
func rotate_camera(delta_yaw: float, delta_pitch: float) -> void:
	delta_yaw *= look_sensitivity
	delta_pitch *= look_sensitivity
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
			# Deadzone: a resting thumb produces sub-pixel jitter that used to
			# spin the view. Sensitivity is a single knob for both axes.
			if delta.length() < TOUCH_DRAG_DEADZONE:
				return
			rotate_camera(delta.x * TOUCH_YAW_SENSITIVITY * look_sensitivity,
				delta.y * TOUCH_PITCH_SENSITIVITY * look_sensitivity)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_dragging = event.pressed
	elif event is InputEventMouseMotion and _mouse_dragging:
		rotate_camera(event.relative.x * YAW_SENSITIVITY, event.relative.y * PITCH_SENSITIVITY)
