## Power score for a combatant — a single number that approximates how much
## combat value they bring. Used by balance tooling and future auto-sizing
## encounter logic. The weights are first-pass guesses; tune them against
## batch-fight results, not intuition.
##
## Score aggregates:
##   - Defensive value: HP, dodge, parry, armor (avoidance diminishes hits;
##     armor scales HP effectively; weight accordingly).
##   - Offensive throughput per round: expected damage-per-AP times total AP,
##     including hit-chance and an abstract armor factor.
##   - Hit chance and MP as flat bonuses.
##
## Keep this deterministic and side-effect-free.
class_name Scoring
extends RefCounted

const W_HP: float = 1.0
const W_MP: float = 0.2
const W_AP: float = 3.0                ## each extra AP is a fraction of a turn
const W_HIT_CHANCE: float = 0.3        ## per hit-chance percentage point
const W_DODGE: float = 0.8             ## per dodge percentage point
const W_PARRY: float = 0.6
const W_ARMOR: float = 0.7             ## per percent of mitigation
const W_WEAPON_EXPECTED_DMG: float = 2.0

static func compute(combatant: Combatant) -> int:
	var s := combatant.stats
	var score: float = 0.0
	score += s.max_hp * W_HP
	score += s.max_mp * W_MP
	score += s.max_action_points * W_AP
	score += s.hit_chance * W_HIT_CHANCE
	score += s.dodge * W_DODGE
	score += s.parry * W_PARRY
	score += s.armor * W_ARMOR
	score += _offensive_value(combatant) * W_WEAPON_EXPECTED_DMG
	return int(round(score))

## Rough damage-per-round contribution from equipment. Attacks per round =
## max_action_points / weapon.action_point_cost; expected damage = mean roll
## × base hit chance. Takes the best profile (cheapest AP cost wins ties —
## it translates to more swings per round).
static func _offensive_value(combatant: Combatant) -> float:
	if combatant.attack_profiles.is_empty():
		return 0.0
	var best_value: float = 0.0
	for p in combatant.attack_profiles:
		var w := p.weapon
		if w.action_point_cost <= 0:
			continue
		var mean_dmg: float = (w.damage_min + w.damage_max) / 2.0
		var swings: float = float(combatant.stats.max_action_points) / float(w.action_point_cost)
		var hit: float = clampf((combatant.stats.hit_chance + w.hit_bonus) / 100.0, 0.05, 0.95)
		var value: float = mean_dmg * swings * hit
		if value > best_value:
			best_value = value
	return best_value
