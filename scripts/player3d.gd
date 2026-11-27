extends CharacterBody3D
## Shadow Protocol - 3D player controller (Phase 3D-1).
##
## Third-person 3D counterpart of the 2D player (scripts/player.gd). The
## movement feel is intentionally identical: same speed constants, same
## acceleration/friction lerp model, same crouch/sprint states. Input is
## camera-relative: the analog vector is projected onto the camera rig's
## yaw basis, so "up" always means "away from the camera".
##
## Unit scale: 1 unit = 1 cm (the 2D grid cell is 48 units). Walk is
## 2.4 m/s, crouch 1.05 m/s, sprint 1.45x - the same cells-per-second
## values the 2D prototype uses.
##
## Deliberately no jump: stealth locomotion only.

const WALK_SPEED: float = 240.0
const CROUCH_SPEED: float = 105.0
const SPRINT_MULTIPLIER: float = 1.45
const ACCELERATION: float = 12.0
const FRICTION: float = 10.0
const GRAVITY: float = 980.0
const STAND_HEIGHT: float = 90.0
const CROUCH_HEIGHT: float = 58.0
const CAMERA_STAND_HEIGHT: float = 72.0
const CAMERA_CROUCH_HEIGHT: float = 50.0
const TURN_RATE: float = 12.0

## Analog movement input, magnitude 0..1 (touch joystick or keyboard).
var move_input: Vector2 = Vector2.ZERO
## Scripted input for headless tests, cutscenes or AI-driven demos. When
## use_input_override is true the device/touch sources are ignored.
var input_override: Vector2 = Vector2.ZERO
var use_input_override: bool = false
var crouching: bool = false
var sprinting: bool = false

## 3D stealth integration (Phase 3D-3): pushed visibility + published noise.
signal visibility_updated(value: float)
var visibility: float = 0.0
var speed_ratio: float = 0.0

const NOISE_INTERVAL: float = 0.25
const NOISE_RADIUS_CROUCHED: float = 90.0
const NOISE_RADIUS_WALKING: float = 220.0
const NOISE_RADIUS_SPRINT: float = 320.0

var _stealth: Node = null
var _noise_timer: float = 0.0

var _touch_layer: Control = null
var _touch_crouch: bool = false
var _touch_sprint: bool = false

@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _visual: Node3D = $Visual
var rig = null  # untyped: avoids freed-instance assignment on restart
@onready var _camera_rig: Node3D = $CameraRig


func _ready() -> void:
	if _visual != null:
		rig = CharacterRig.build_player(_visual)
	_apply_posture(0.0, true)


## Registers the shared 2D touch layer (scripts/mobile_controls.gd). The
## same overlay drives both prototypes; nothing about it is duplicated.
func set_touch_controls(layer: Control) -> void:
	_touch_layer = layer


## Registers the 3D stealth core (StealthSystem3D owned by main3d).
func set_stealth(system: Node) -> void:
	_stealth = system


func set_touch_crouch(active: bool) -> void:
	_touch_crouch = active


func set_touch_sprint(active: bool) -> void:
	_touch_sprint = active


## Current camera yaw used as the movement basis (0 when no rig exists).
func camera_yaw() -> float:
	if _camera_rig != null and _camera_rig.has_method("get_yaw"):
		return _camera_rig.get_yaw()
	return 0.0


func _physics_process(delta: float) -> void:
	move_input = _read_move_input()
	crouching = Input.is_action_pressed("crouch") or _touch_crouch
	sprinting = (Input.is_action_pressed("sprint") or _touch_sprint) and not crouching

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var max_speed: float = CROUCH_SPEED if crouching else WALK_SPEED
	if sprinting:
		max_speed *= SPRINT_MULTIPLIER

	var yaw: float = camera_yaw()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var desired_dir: Vector3 = right * move_input.x + forward * (-move_input.y)
	if desired_dir.length() > 1.0:
		desired_dir = desired_dir.normalized()

	speed_ratio = clampf(Vector2(velocity.x, velocity.z).length() / maxf(max_speed, 1.0), 0.0, 1.0)
	var desired := Vector3(desired_dir.x * max_speed, 0.0, desired_dir.z * max_speed)
	var weight: float = ACCELERATION if desired_dir.length_squared() > 0.0001 else FRICTION
	var flat := Vector3(velocity.x, 0.0, velocity.z).lerp(desired, minf(1.0, weight * delta))
	velocity.x = flat.x
	velocity.z = flat.z

	move_and_slide()
	_update_stealth()
	_update_noise(delta)

	# Face the movement direction (visual only, never the collision body).
	if rig != null:
		rig.animate(delta, Vector2(velocity.x, velocity.z).length(), crouching, sprinting)
	if _camera_rig != null and _camera_rig.has_method("set_sprinting"):
		_camera_rig.set_sprinting(sprinting and Vector2(velocity.x, velocity.z).length() > 20.0)
	if desired_dir.length_squared() > 0.0001 and _visual != null:
		var target_yaw: float = atan2(-desired_dir.x, -desired_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(1.0, TURN_RATE * delta))

	_apply_posture(delta)


func _read_move_input() -> Vector2:
	if use_input_override:
		return input_override
	if _touch_layer != null and is_instance_valid(_touch_layer) and _touch_layer.visible:
		return _touch_layer.get_movement_vector()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Smoothly blends the capsule and camera height between stand and crouch.
func _apply_posture(delta: float, immediate: bool = false) -> void:
	if _collider == null or _camera_rig == null:
		return
	var target_height: float = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var target_cam: float = CAMERA_CROUCH_HEIGHT if crouching else CAMERA_STAND_HEIGHT
	var shape := _collider.shape as CapsuleShape3D
	if shape != null:
		shape.height = target_height if immediate else lerpf(shape.height, target_height, minf(1.0, 10.0 * delta))
		_collider.position.y = shape.height * 0.5
		if _visual != null:
			_visual.scale.y = 1.0 if immediate else lerpf(_visual.scale.y, shape.height / STAND_HEIGHT, minf(1.0, 10.0 * delta))
	_camera_rig.position.y = target_cam if immediate \
		else lerpf(_camera_rig.position.y, target_cam, minf(1.0, 10.0 * delta))


## Pushes live visibility from the 3D stealth core (Phase 3D-3).
func _update_stealth() -> void:
	if _stealth == null:
		return
	visibility = _stealth.compute_visibility(global_position, crouching, speed_ratio)
	visibility_updated.emit(visibility)


## Publishes movement noise at the same 0.25 s cadence and radii as the 2D
## player, through StealthSystem3D.publish_noise().
func _update_noise(delta: float) -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() < 5.0:
		_noise_timer = 0.0
		return
	_noise_timer += delta
	if _noise_timer >= NOISE_INTERVAL:
		_noise_timer = 0.0
		if _stealth != null:
			_stealth.publish_noise(global_position, current_noise_radius(), &"player", movement_state())


## Same radius formula as scripts/player.gd.
func current_noise_radius() -> float:
	if crouching:
		return NOISE_RADIUS_CROUCHED
	if sprinting:
		return NOISE_RADIUS_SPRINT
	return NOISE_RADIUS_WALKING * (0.55 + 0.45 * speed_ratio)


## Movement state label carried by the noise event.
func movement_state() -> StringName:
	if crouching:
		return &"crouch"
	if sprinting:
		return &"sprint"
	return &"walk"
