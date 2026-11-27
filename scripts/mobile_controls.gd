extends Control
## Shadow Protocol - native-feeling multi-touch controls.
##
## Left half of the screen: floating analog joystick (base appears where
## the finger lands, follows long drags, dead-zone handled, auto-centers).
## Right side: circular action buttons for CROUCH (toggle), SPRINT (toggle)
## and INTERACT (press). Every touch is tracked by pointer index so the
## joystick and buttons never interfere with each other.
##
## Keyboard users are unaffected: the layer hides itself when no
## touchscreen is available and the player falls back to InputMap actions.

signal crouch_toggled(active: bool)
signal sprint_toggled(active: bool)
signal interact_pressed()
## Phase 3D-10 weapon controls.
signal fire_pressed()
signal reload_pressed()
signal mode_pressed()

const JOYSTICK_MAX_RADIUS: float = 110.0
const JOYSTICK_DEAD_ZONE: float = 0.12
const JOYSTICK_ZONE_WIDTH_RATIO: float = 0.45
const BUTTON_RADIUS: float = 42.0
const INTERACT_RADIUS: float = 52.0
const FIRE_RADIUS: float = 58.0
const UTILITY_RADIUS: float = 34.0

## NEON NOIR touch language (visual upgrade): cyan-tinted translucent
## fills, brighter rings, clear pressed states. Geometry (centers,
## radii, hit zones) is unchanged - only presentation.
const COLOR_BASE := Color(0.30, 0.85, 0.90, 0.10)
const COLOR_RING := Color(0.55, 0.90, 0.95, 0.45)
const COLOR_KNOB := Color(0.45, 0.95, 1.0, 0.85)
const COLOR_BTN := Color(0.30, 0.85, 0.90, 0.13)
const COLOR_BTN_PRESSED := Color(0.45, 0.95, 1.0, 0.32)
const COLOR_BTN_TEXT := Color(0.88, 0.93, 0.97, 0.95)

var _joystick_index: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO
var _joystick_visible: bool = false
## Hybrid stick (3D-13): a fixed home base is always drawn at bottom-left;
## touching the left half relocates the base to the finger and releasing eases
## it back home. `_stick_base` is where the base is drawn right now.
var _stick_home: Vector2 = Vector2.ZERO
var _stick_base: Vector2 = Vector2.ZERO
var _stick_returning: bool = false
var _buttons: Dictionary = {}
var _button_touches: Dictionary = {}  # pointer index -> button name
var _crouch_active: bool = false
var _sprint_active: bool = false


## Reserved gameplay region of the floating joystick (left 45% of the
## screen, below mid-height where thumbs operate it). HUD must stay
## out of this rectangle. Shared truth for layout and layout tests.
func joystick_reserved_rect() -> Rect2:
	var screen: Vector2 = get_viewport_rect().size
	return Rect2(Vector2(0.0, screen.y * 0.45), Vector2(screen.x * 0.45, screen.y * 0.55))

## Reserved region of the action buttons (bottom-right cluster).
func buttons_reserved_rect() -> Rect2:
	var screen: Vector2 = get_viewport_rect().size
	return Rect2(screen - Vector2(340.0, 340.0), Vector2(340.0, 340.0))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT
	# Only show the touch overlay on real touch devices (Android, touchscreens).
	# The explicit touch_debug project setting (shadow_protocol/touch_debug,
	# default false) forces the overlay for desktop layout testing; it is
	# read once here so toggling it takes effect on the next scene load.
	visible = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("android") \
		or ProjectSettings.get_setting("shadow_protocol/touch_debug", false)
	_layout_buttons()
	get_viewport().size_changed.connect(_layout_buttons)


func _layout_buttons() -> void:
	var screen: Vector2 = get_viewport_rect().size
	_buttons = {
		# Primary actions sit in the thumb arc: FIRE outermost, USE just above it.
		"interact": {
			"center": Vector2(screen.x - 168.0, screen.y - 150.0),
			"radius": 46.0,
			"label": "USE",
			"pressed": false,
		},
		"fire": {
			"center": Vector2(screen.x - 112.0, screen.y - 268.0),
			"radius": 60.0,
			"label": "FIRE",
			"pressed": false,
		},
		"reload": {
			"center": Vector2(screen.x - 316.0, screen.y - 262.0),
			"radius": 34.0,
			"label": "RLD",
			"pressed": false,
		},
		"mode": {
			"center": Vector2(screen.x - 330.0, screen.y - 170.0),
			"radius": 32.0,
			"label": "MODE",
			"pressed": false,
		},
		# Secondary controls are smaller and live inboard of the primaries.
		"crouch": {
			"center": Vector2(screen.x - 126.0, screen.y - 54.0),
			"radius": 40.0,
			"label": "CROUCH",
			"pressed": false,
		},
		"sprint": {
			"center": Vector2(screen.x - 268.0, screen.y - 62.0),
			"radius": 42.0,
			"label": "SPRINT",
			"pressed": false,
		},
	}
	# Toggle buttons keep their active state across relayouts.
	_buttons["crouch"]["pressed"] = _crouch_active
	_buttons["sprint"]["pressed"] = _sprint_active
	# Fixed stick home, clear of the HUD weapon panel (which moved up/right).
	_stick_home = Vector2(150.0, screen.y - 150.0)
	if not _joystick_visible:
		_stick_base = _stick_home
	queue_redraw()


## Current analog movement vector, magnitude in 0..1 (dead zone applied).
## Centre of a named action button in canvas space (tests and tooling).
func button_center(name: String) -> Vector2:
	if _buttons.has(name):
		return _buttons[name]["center"]
	return Vector2.ZERO


func get_movement_vector() -> Vector2:
	return _joystick_vector


## True when a touch at this position is owned by the touch layer (joystick
## zone or one of the action buttons) and must NOT be reused for another
## gesture such as 3D camera rotation. Single source of truth for the
## button geometry so the 3D camera rig can never conflict with
## SPRINT/CROUCH/USE. Purely additive: no existing behaviour changes.
func is_position_owned(pos: Vector2) -> bool:
	pos = to_canvas(pos)
	for name: String in _buttons:
		var btn: Dictionary = _buttons[name]
		if pos.distance_to(btn["center"]) <= btn["radius"]:
			return true
	var zone_width: float = get_viewport_rect().size.x * JOYSTICK_ZONE_WIDTH_RATIO
	return pos.x <= zone_width


## Normalises an incoming touch position into canvas space.
##
## Godot applies the stretch transform to canvas items, but on Android the
## screen events can arrive in window pixels. Without this the joystick
## zone (a hard cut at 42% of the canvas width) rejects genuine left-half
## drags on tall 20:9 screens, which is exactly what device testing
## showed. The check is per event and idempotent: a position already
## inside the canvas rect is returned untouched.
func to_canvas(pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return pos
	var rect: Vector2 = vp.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return pos
	if pos.x <= rect.x + 1.0 and pos.y <= rect.y + 1.0:
		return pos
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	if win.x <= rect.x + 1.0:
		return pos
	return Vector2(pos.x * rect.x / win.x, pos.y * rect.y / win.y)


func _process(delta: float) -> void:
	# Hybrid stick: after release the base eases back to its fixed home.
	if _stick_returning and not _joystick_visible:
		_stick_base = _stick_base.lerp(_stick_home, minf(1.0, 12.0 * delta))
		if _stick_base.distance_to(_stick_home) < 0.5:
			_stick_base = _stick_home
			_stick_returning = false
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_press(to_canvas(event.position), event.index)
		else:
			_handle_release(event.index)
	elif event is InputEventScreenDrag and event.index == _joystick_index:
		_update_joystick(to_canvas(event.position))


func _handle_press(pos: Vector2, index: int) -> void:
	# Buttons win over the joystick zone if the touch lands on one.
	for name: String in _buttons:
		var btn: Dictionary = _buttons[name]
		if pos.distance_to(btn["center"]) <= btn["radius"]:
			_button_touches[index] = name
			_press_button(name)
			return
	var zone_width: float = get_viewport_rect().size.x * JOYSTICK_ZONE_WIDTH_RATIO
	if pos.x <= zone_width:
		_joystick_index = index
		_joystick_origin = pos
		_stick_base = pos
		_stick_returning = false
		_joystick_vector = Vector2.ZERO
		_joystick_visible = true
		queue_redraw()


func _handle_release(index: int) -> void:
	if index == _joystick_index:
		_joystick_index = -1
		_joystick_vector = Vector2.ZERO
		_joystick_visible = false
		_stick_returning = true
		queue_redraw()
	elif _button_touches.has(index):
		var name: String = _button_touches[index]
		_button_touches.erase(index)
		# Toggles keep their latched state; momentary buttons reset.
		if name == "sprint":
			_buttons[name]["pressed"] = false
			sprint_toggled.emit(false)
		elif name == "interact" or name == "fire" or name == "reload" or name == "mode":
			_buttons[name]["pressed"] = false
		elif name == "fire" or name == "reload" or name == "mode":
			_buttons[name]["pressed"] = false
		queue_redraw()


func _update_joystick(pos: Vector2) -> void:
	var offset: Vector2 = pos - _joystick_origin
	var distance: float = offset.length()
	if distance > JOYSTICK_MAX_RADIUS:
		# Base follows the finger on long drags ("floating" joystick).
		_joystick_origin += offset - offset.normalized() * JOYSTICK_MAX_RADIUS
		offset = offset.normalized() * JOYSTICK_MAX_RADIUS
	var normalized: Vector2 = offset / JOYSTICK_MAX_RADIUS
	var magnitude: float = normalized.length()
	if magnitude < JOYSTICK_DEAD_ZONE:
		_joystick_vector = Vector2.ZERO
	else:
		# Rescale above the dead zone so low magnitudes are not lost.
		var scaled: float = (magnitude - JOYSTICK_DEAD_ZONE) / (1.0 - JOYSTICK_DEAD_ZONE)
		# Gentle response curve: small tilts register, large tilts stay linear
		# so steering feels immediate instead of floaty.
		scaled = pow(scaled, 0.85)
		_joystick_vector = normalized.normalized() * scaled
	queue_redraw()


func _press_button(name: String) -> void:
	match name:
		"interact":
			_buttons[name]["pressed"] = true
			interact_pressed.emit()
		"crouch":
			_crouch_active = not _crouch_active
			_buttons[name]["pressed"] = _crouch_active
			crouch_toggled.emit(_crouch_active)
		"sprint":
			_sprint_active = not _sprint_active
			_buttons[name]["pressed"] = _sprint_active
			sprint_toggled.emit(_sprint_active)
		"fire":
			_buttons[name]["pressed"] = true
			fire_pressed.emit()
		"reload":
			_buttons[name]["pressed"] = true
			reload_pressed.emit()
		"mode":
			_buttons[name]["pressed"] = true
			mode_pressed.emit()
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var base: Vector2 = _stick_base if _joystick_visible else _stick_home
	var idle_alpha: float = 0.55 if not _joystick_visible else 1.0
	var base_fill := COLOR_BASE
	base_fill.a *= idle_alpha
	var ring := COLOR_RING
	ring.a *= idle_alpha
	draw_circle(base, JOYSTICK_MAX_RADIUS * 0.55, base_fill)
	draw_arc(base, JOYSTICK_MAX_RADIUS * 0.55, 0.0, TAU, 40, ring, 2.0)
	var knob: Vector2 = base + _joystick_vector * JOYSTICK_MAX_RADIUS * 0.55
	var knob_color := COLOR_KNOB
	knob_color.a *= idle_alpha
	draw_circle(knob, 26.0, knob_color)
	for name: String in _buttons:
		var btn: Dictionary = _buttons[name]
		var fill: Color = COLOR_BTN_PRESSED if btn["pressed"] else COLOR_BTN
		draw_circle(btn["center"], btn["radius"], fill)
		draw_arc(btn["center"], btn["radius"], 0.0, TAU, 40, COLOR_RING, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			btn["center"] + Vector2(-28.0, 7.0),
			btn["label"],
			HORIZONTAL_ALIGNMENT_CENTER,
			56.0,
			13,
			COLOR_BTN_TEXT
		)
		# Subtle pressed ring flash: a second arc just inside the ring.
		if btn["pressed"]:
			draw_arc(btn["center"], btn["radius"] - 4.0, 0.0, TAU, 40,
				Color(0.75, 1.0, 1.0, 0.5), 2.0)
