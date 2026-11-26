class_name SquadDirector
extends Node
## Shadow Protocol - squad coordination (Phase 3D-10).
##
## Port of the web build's SquadDirector (enemyAI.ts): guards share threat
## knowledge, downed bodies are noticed, and two or more alerted guards
## split into a suppressor + flanker pair. Also carries the Act-3 patrol
## escalation flag (web commit 88c88f6).
##
## Deterministic and tick-based (0.45 s cadence, like the web build) so it
## is fully testable headless.

signal guard_down_reported(guard_id: StringName, position: Vector3)
signal squad_alerted(position: Vector3, source_id: StringName)
signal flank_order(guard_id: StringName, position: Vector3)

const UPDATE_INTERVAL: float = 0.45
const ALERT_PROPAGATION_RADIUS: float = 520.0
const DOWNED_NOTICE_RADIUS: float = 520.0
const FLANK_COOLDOWN: float = 4.0
const ACT3_PATROL_SPEED_SCALE: float = 1.18

var guards: Array = []
var downed_bodies: Array = []      # [{id, position, discovered}]
var act3_active: bool = false
var alerts_sent: int = 0
var downed_count: int = 0

var _accum: float = 0.0
var _flank_cooldown: float = 0.0


func register_guard(guard: Node) -> void:
	if guard == null or guards.has(guard):
		return
	guards.append(guard)
	if guard.has_method("set_squad"):
		guard.set_squad(self)


func clear() -> void:
	guards.clear()
	downed_bodies.clear()
	_accum = 0.0
	_flank_cooldown = 0.0
	alerts_sent = 0
	downed_count = 0


func alive_guards() -> Array:
	var out: Array = []
	for g in guards:
		if not is_instance_valid(g):
			continue
		if g.has_method("is_downed") and g.is_downed():
			continue
		out.append(g)
	return out


## A guard reported a body: every other guard nearby goes to investigate,
## and the body is recorded once so it is never re-reported.
func report_downed(guard: Node) -> void:
	if guard == null or not is_instance_valid(guard):
		return
	var pos: Vector3 = guard.global_position
	var gid: StringName = guard.get("enemy_id") if "enemy_id" in guard else &"guard"
	for body: Dictionary in downed_bodies:
		if body["id"] == gid:
			return
	downed_bodies.append({"id": gid, "position": pos, "discovered": false})
	downed_count += 1
	guard_down_reported.emit(gid, pos)
	for other in alive_guards():
		if other == guard:
			continue
		if other.global_position.distance_to(pos) <= DOWNED_NOTICE_RADIUS:
			if other.has_method("notice_downed_body"):
				other.notice_downed_body(pos)


## Broadcasts a threat position to the whole squad (radio callout).
func broadcast_alert(source_id: StringName, position: Vector3) -> void:
	alerts_sent += 1
	squad_alerted.emit(position, source_id)
	for g in alive_guards():
		if g.get("enemy_id") == source_id:
			continue
		if g.has_method("receive_squad_alert"):
			g.receive_squad_alert(position, source_id)


func _process(delta: float) -> void:
	if _flank_cooldown > 0.0:
		_flank_cooldown = maxf(0.0, _flank_cooldown - delta)
	_accum += delta
	if _accum < UPDATE_INTERVAL:
		return
	_accum = 0.0
	_tick()


func _tick() -> void:
	var alerted: Array = []
	for g in alive_guards():
		if String(g.get("state")) == "alert":
			alerted.append(g)
	if alerted.size() < 2 or _flank_cooldown > 0.0:
		return
	# Suppressor = closest to the shared threat; flanker = the other one.
	var lead = alerted[0]
	for g in alerted:
		if g.has_method("can_see_player") and g.can_see_player():
			lead = g
			break
	var focus: Vector3 = lead.get("last_known_player_position")
	var suppressor = alerted[0]
	var best: float = INF
	for g in alerted:
		var d: float = g.global_position.distance_to(focus)
		if g.has_method("can_see_player") and g.can_see_player():
			d -= 75.0
		if d < best:
			best = d
			suppressor = g
	for g in alerted:
		if g == suppressor:
			continue
		if g.has_method("order_flank"):
			g.order_flank(focus)
			flank_order.emit(g.get("enemy_id"), focus)
			_flank_cooldown = FLANK_COOLDOWN
			return


## Act-3 escalation: patrol routes tighten and speed picks up. Kept as a
## flag the guards read so their FSM stays untouched.
func set_act3(active: bool) -> void:
	act3_active = active
	for g in guards:
		if is_instance_valid(g) and g.has_method("set_act3"):
			g.set_act3(active)


func speed_scale() -> float:
	return ACT3_PATROL_SPEED_SCALE if act3_active else 1.0
