class_name SpatialAudio
extends Node
## Shadow Protocol - procedural spatial audio (Phase 3D-10).
##
## Port of the web build's computeSpatial (soundEngine.ts) plus a compact
## procedural voice bank. Everything is synthesised at runtime: no audio
## assets, matching the project's no-external-assets rule.
##
## FeedbackManager keeps its five existing cues untouched; this layer adds
## world-positioned events (weapon reports, footsteps by surface, impacts).

const MAX_VOICES: int = 12
const DEFAULT_MAX_RANGE: float = 460.0
const DEFAULT_MIN_RANGE: float = 42.0
const MIX_RATE: int = 22050

## Distance attenuation + stereo pan, identical to the web formula:
## gain = t*t*(0.28+0.72*t), pan clamped to +/-0.85 with a near blend.
static func compute_spatial(source: Vector3, listener: Vector3, listener_yaw: float,
		max_range: float = DEFAULT_MAX_RANGE, min_range: float = DEFAULT_MIN_RANGE,
		min_gain_floor: float = 0.0) -> Dictionary:
	var dx: float = source.x - listener.x
	var dz: float = source.z - listener.z
	var dist: float = sqrt(dx * dx + dz * dz)
	var gain: float = 0.0
	var pan: float = 0.0
	if dist < max_range:
		if dist <= min_range:
			gain = 1.0
		else:
			var t: float = 1.0 - (dist - min_range) / maxf(1.0, max_range - min_range)
			gain = t * t * (0.28 + 0.72 * t)
		if dist > 0.5:
			var right_x: float = cos(listener_yaw)
			var right_z: float = -sin(listener_yaw)
			var dot_right: float = (dx / dist) * right_x + (dz / dist) * right_z
			var near_blend: float = dist / maxf(1.0, min_range) if dist < min_range else 1.0
			pan = clampf(dot_right * 0.85 * near_blend, -0.85, 0.85)
	if min_gain_floor > 0.0 and gain < min_gain_floor:
		gain = min_gain_floor
	return {"gain": gain, "pan": pan, "distance": dist}


var listener: Node3D = null
var muted: bool = false
var played_events: int = 0
var last_event: StringName = &""
var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_cursor: int = 0


func _ready() -> void:
	_build_bank()
	for i in range(MAX_VOICES):
		var p := AudioStreamPlayer3D.new()
		p.max_db = 0.0
		p.unit_size = 60.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_voices.append(p)


## Procedural voice bank: short synthesised bursts per event family.
func _build_bank() -> void:
	_bank[&"shot_suppressed"] = _make_noise(0.07, 0.16, 260.0)
	_bank[&"shot_loud"] = _make_noise(0.16, 0.55, 140.0)
	_bank[&"shot_rifle"] = _make_noise(0.22, 0.75, 105.0)
	_bank[&"shot_guard"] = _make_noise(0.18, 0.62, 120.0)
	_bank[&"impact"] = _make_noise(0.06, 0.30, 620.0)
	_bank[&"step_concrete"] = _make_noise(0.045, 0.10, 420.0)
	_bank[&"step_metal"] = _make_noise(0.055, 0.16, 900.0)
	_bank[&"step_vent"] = _make_noise(0.06, 0.20, 1100.0)
	_bank[&"door"] = _make_tone(320.0, 180.0, 0.18)
	_bank[&"terminal"] = _make_tone(760.0, 1180.0, 0.14)
	_bank[&"alarm"] = _make_tone(520.0, 880.0, 0.30)


func _make_noise(duration: float, amp: float, bright: float) -> AudioStreamWAV:
	var frames: int = int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bright)
	var lp: float = 0.0
	for i in range(frames):
		var env: float = 1.0 - float(i) / float(frames)
		var white: float = rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, white, clampf(bright / 1200.0, 0.05, 0.9))
		var s: int = int(clampf(lp * env * env * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _make_tone(from_hz: float, to_hz: float, duration: float) -> AudioStreamWAV:
	var frames: int = int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase: float = 0.0
	for i in range(frames):
		var t: float = float(i) / float(frames)
		var hz: float = lerpf(from_hz, to_hz, t)
		phase += TAU * hz / float(MIX_RATE)
		var env: float = sin(PI * t)
		data.encode_s16(i * 2, int(clampf(sin(phase) * env * 0.35, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func has_event(event: StringName) -> bool:
	return _bank.has(event)


func event_names() -> Array:
	return _bank.keys()


## Plays a world-positioned procedural cue. Returns the spatial result.
func play_at(event: StringName, position: Vector3, max_range: float = DEFAULT_MAX_RANGE) -> Dictionary:
	last_event = event
	if muted or not _bank.has(event):
		return {"gain": 0.0, "pan": 0.0, "distance": 0.0}
	var listener_pos: Vector3 = listener.global_position if is_instance_valid(listener) else Vector3.ZERO
	var yaw: float = 0.0
	if is_instance_valid(listener) and "yaw" in listener:
		yaw = float(listener.yaw)
	var spatial: Dictionary = compute_spatial(position, listener_pos, yaw, max_range)
	if float(spatial["gain"]) <= 0.001:
		return spatial
	var voice: AudioStreamPlayer3D = _voices[_voice_cursor % _voices.size()]
	_voice_cursor += 1
	voice.stream = _bank[event]
	voice.global_position = position
	voice.volume_db = linear_to_db(maxf(0.02, float(spatial["gain"])))
	voice.play()
	played_events += 1
	return spatial


## Weapon report chosen by the shot's own suppression/caliber profile.
func weapon_report(shot: Dictionary, position: Vector3) -> Dictionary:
	var event: StringName = &"shot_suppressed"
	if not bool(shot.get("suppressed", true)):
		var cat: String = String(WeaponSystem.SPECS.get(shot.get("weapon", &""), {}).get("category", "pistol"))
		event = &"shot_rifle" if cat == "rifle" else &"shot_loud"
	return play_at(event, position, float(shot.get("noise_radius", 200.0)))


## Footstep variant by surface tag ("concrete" / "metal" / "vent").
func footstep(surface: StringName, position: Vector3) -> Dictionary:
	var event: StringName = &"step_concrete"
	match surface:
		&"metal":
			event = &"step_metal"
		&"vent":
			event = &"step_vent"
	return play_at(event, position, 220.0)
