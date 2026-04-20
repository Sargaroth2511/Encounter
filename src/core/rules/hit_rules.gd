## Attack resolution pipeline. Pure, stateless, deterministic via SeededRng.
##
## Order of checks:
##   1. Hit roll (attacker.hit_chance + weapon.hit_bonus, clamped)
##   2. Dodge roll (defender.dodge)
##   3. Parry roll (defender.parry + best parry_bonus from their weapons)
##   4. Damage roll + armor mitigation (percent)
##
## A miss short-circuits all later steps, same for dodge and parry. Parry is
## gated by `weapon.parryable` and by the attacker weapon's
## `parry_allowed_kinds` restriction (empty list = any melee kind allowed).
##
## Returns a dictionary — a plain Dictionary rather than a typed result so
## CombatEngine can forward fields straight into event payloads.
class_name HitRules
extends RefCounted

enum Outcome { HIT, MISS, DODGED, PARRIED }

const HIT_MIN: int = 5
const HIT_MAX: int = 95
const AVOID_MAX: int = 95
const ARMOR_K: float = 50.0
const ARMOR_CEILING: float = 0.75

static func outcome_name(o: int) -> String:
	return Outcome.keys()[o].to_lower()

static func resolve(attacker: Combatant, weapon: WeaponDef, defender: Combatant, rng: SeededRng) -> Dictionary:
	var result: Dictionary = {
		"outcome": Outcome.HIT,
		"damage": 0,
		"raw_damage": 0,
		"armor_pct": 0,
		"hit_chance": 0,
		"dodge_chance": 0,
		"parry_chance": 0,
		"parry_weapon_id": "",
	}

	# 1) HIT
	var hit_chance: int = clampi(attacker.stats.hit_chance + weapon.hit_bonus, HIT_MIN, HIT_MAX)
	result["hit_chance"] = hit_chance
	if rng.randi_range(1, 100) > hit_chance:
		result["outcome"] = Outcome.MISS
		return result

	# 2) DODGE
	var dodge_chance: int = clampi(defender.stats.dodge, 0, AVOID_MAX)
	result["dodge_chance"] = dodge_chance
	if dodge_chance > 0 and rng.randi_range(1, 100) <= dodge_chance:
		result["outcome"] = Outcome.DODGED
		return result

	# 3) PARRY
	var parry_weapon := _best_parry_weapon(defender, weapon)
	if parry_weapon != null:
		var parry_chance: int = clampi(defender.stats.parry + parry_weapon.parry_bonus, 0, AVOID_MAX)
		result["parry_chance"] = parry_chance
		result["parry_weapon_id"] = String(parry_weapon.weapon_id)
		if parry_chance > 0 and rng.randi_range(1, 100) <= parry_chance:
			result["outcome"] = Outcome.PARRIED
			return result

	# 4) DAMAGE + ARMOR
	var raw: int = rng.randi_range(weapon.damage_min, weapon.damage_max)
	var armor_total: float = float(defender.stats.armor)
	var mit: float = clampf(armor_total / (armor_total + ARMOR_K), 0.0, ARMOR_CEILING)
	var mitigated: int = int(floor(raw * (1.0 - mit)))
	if raw > 0:
		mitigated = max(1, mitigated)
	result["raw_damage"] = raw
	result["armor_pct"] = int(round(mit * 100.0))
	result["damage"] = mitigated
	return result

## Returns the defender's weapon best suited to parry `incoming`, or null if
## the attack cannot be parried at all (incoming.parryable=false, or no
## defender weapon satisfies the parry_allowed_kinds restriction).
static func _best_parry_weapon(defender: Combatant, incoming: WeaponDef) -> WeaponDef:
	if not incoming.parryable:
		return null
	if defender.attack_profiles.is_empty():
		return null
	var best: WeaponDef = null
	for p in defender.attack_profiles:
		var w := p.weapon
		if not incoming.parry_allowed_kinds.is_empty() and not incoming.parry_allowed_kinds.has(w.weapon_kind):
			continue
		if best == null or w.parry_bonus > best.parry_bonus:
			best = w
	return best
