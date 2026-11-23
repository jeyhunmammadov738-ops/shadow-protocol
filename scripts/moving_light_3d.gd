class_name MovingLight3D
extends LightSource3D
## Shadow Protocol - 3D moving light (Phase 3D-3): ping-pong between two
## points on the XZ plane. Same deterministic triangle-wave timing as the
## 2D MovingLight, so both produce identical positions for identical
## parameters and elapsed time.

@export var point_a: Vector3 = Vector3.ZERO
@export var point_b: Vector3 = Vector3.ZERO
@export_range(10.0, 400.0, 1.0) var speed: float = 80.0

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	advance_to(_elapsed)


## Pure position function of elapsed time (deterministic, testable).
func advance_to(elapsed: float) -> void:
	var span: Vector3 = point_b - point_a
	var length: float = span.length()
	if length < 0.01:
		return
	var period: float = (2.0 * length) / speed
	var phase: float = fmod(elapsed, period) / period * 2.0
	var t: float = phase if phase <= 1.0 else 2.0 - phase
	global_position = point_a.lerp(point_b, t)
