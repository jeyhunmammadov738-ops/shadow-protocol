class_name PlayerHealth
extends RefCounted
## Shadow Protocol - player health and armour (Phase 3D-11).
##
## New feature: the web build never damages the player (its only
## applyBallisticHit call sites are player shots hitting guards), so this is
## designed from the primitives that already exist rather than ported.
##
## Balance intent: the first alert must never kill instantly. Armour soaks
## the opening burst, hits are reduced by the cover factors the stealth
## system already computes (0.62 wall / 0.55 low cover), and there is a
## short post-hit grace so the player can break line of sight.

signal damaged(amount: float, from_position: Vector3)
signal died()
signal healed(amount: float)

const MAX_HEALTH: float = 100.0
const MAX_ARMOR: float = 40.0
const ARMOR_ABSORB: float = 0.7          # share of a hit the armour eats
const HIT_GRACE_SEC: float = 0.55        # invulnerability window after a hit
const REGEN_DELAY_SEC: float = 6.0
const REGEN_PER_SEC: float = 4.0
const LOW_HEALTH: float = 30.0

var health: float = MAX_HEALTH
var armor: float = MAX_ARMOR
var alive: bool = true
var hits_taken: int = 0
var damage_taken: float = 0.0
var last_hit_from: Vector3 = Vector3.ZERO
var last_hit_dir: Vector3 = Vector3.ZERO

var _grace: float = 0.0
var _regen_delay: float = 0.0


func reset() -> void:
	health = MAX_HEALTH
	armor = MAX_ARMOR
	alive = true
	hits_taken = 0
	damage_taken = 0.0
	_grace = 0.0
	_regen_delay = 0.0
	last_hit_from = Vector3.ZERO
	last_hit_dir = Vector3.ZERO


func health_ratio() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


func armor_ratio() -> float:
	return clampf(armor / MAX_ARMOR, 0.0, 1.0)


func is_low() -> bool:
	return alive and health <= LOW_HEALTH


func can_be_hit() -> bool:
	return alive and _grace <= 0.0


## Applies one incoming hit. [param cover_factor] comes from CoverSystem
## (1.0 exposed, 0.62 wall cover, 0.55 low cover). Returns the damage that
## actually landed, 0.0 when the grace window absorbed it.
func apply_hit(raw_damage: float, from_position: Vector3, cover_factor: float = 1.0) -> float:
	if not can_be_hit():
		return 0.0
	var scaled: float = raw_damage * clampf(cover_factor, 0.0, 1.0)
	var absorbed: float = minf(armor, scaled * ARMOR_ABSORB)
	armor -= absorbed
	var to_health: float = scaled - absorbed
	health = maxf(0.0, health - to_health)
	hits_taken += 1
	damage_taken += to_health
	_grace = HIT_GRACE_SEC
	_regen_delay = REGEN_DELAY_SEC
	last_hit_from = from_position
	var dir: Vector3 = from_position - Vector3.ZERO
	last_hit_dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.ZERO
	damaged.emit(to_health, from_position)
	if health <= 0.0 and alive:
		alive = false
		died.emit()
	return to_health


func tick(delta: float) -> void:
	if not alive:
		return
	_grace = maxf(0.0, _grace - delta)
	if _regen_delay > 0.0:
		_regen_delay = maxf(0.0, _regen_delay - delta)
		return
	if health < MAX_HEALTH:
		var before: float = health
		health = minf(MAX_HEALTH, health + REGEN_PER_SEC * delta)
		if health > before:
			healed.emit(health - before)
