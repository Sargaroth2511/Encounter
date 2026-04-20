## Power score for a combatant — a single number representing combat budget.
##
## Score 100 = baseline hero (Aria at start). A foe at score 100 should have
## roughly 50/50 odds vs Aria. Scores are relative — 200 vs 210 gives the
## same advantage as 100 vs 105.
##
## Expected win probability: P(A wins) = score_A / (score_A + score_B).
##
## Each stat has a fixed cost-per-point derived from mirror calibration.
## Weapon contribution is scored via offensive_value (DPR).
## Keep this deterministic and side-effect-free.
class_name Scoring
extends RefCounted

const COST_TABLE_PATH: String = "res://assets/data/balance/cost_table.json"
const WEIGHTS_PATH: String = "res://assets/data/balance/score_weights.json"

## New linear cost table: { stat_costs: { stat: cost, ... }, offensive_cost: float }
static var _cost_table: Dictionary = {}
## Old curve params (kept for backward-compat / calibrate_weights.py).
static var _params: Dictionary = {}

## Saturating curve (kept for backward compat and general use):
## f(x) = scale * (1 - e^(-(x^steepness) / midpoint))
static func curve(x: float, scale: float, midpoint: float, steepness: float) -> float:
	if x <= 0.0 or scale <= 0.0 or midpoint <= 0.0:
		return 0.0
	var powered: float = pow(x, steepness)
	return scale * (1.0 - exp(-powered / midpoint))

## --- Primary scoring: DPR × EHP model ------------------------------------
##
## score = _total_dpr(c) × _effective_hp(c) × normalization_factor
##
## DPR: greedy fill of the AP budget with attack profiles sorted by cost
## descending (most expensive first — matches combat_controller behaviour).
## Uses floor() for swings so AP dead zones are correctly handled.
##
## EHP: HP scaled by avoidance (dodge + parry sequential rolls, same as
## HitRules) and armor mitigation (armor/(armor+K)). Captures how hard
## the combatant actually is to kill in practice.
##
## normalization_factor: stored in cost_table.json, tuned so that the
## baseline hero (Aria with starting stats) produces score = 100.

static func compute(combatant: Combatant) -> int:
	_ensure_cost_table()
	var armor_k := float(_cost_table.get("armor_k", 50.0))
	var norm    := float(_cost_table.get("normalization_factor", 0.4006))
	var dpr := _total_dpr(combatant)
	var ehp := _effective_hp(combatant, armor_k)
	return int(round(dpr * ehp * norm))

## DPR: greedy AP fill, profiles sorted by cost descending.
static func _total_dpr(combatant: Combatant) -> float:
	if combatant.attack_profiles.is_empty():
		return 0.0
	var sorted: Array = combatant.attack_profiles.duplicate()
	sorted.sort_custom(func(a, b): return a.weapon.action_point_cost > b.weapon.action_point_cost)
	var remaining_ap := combatant.stats.max_action_points
	var total := 0.0
	for p in sorted:
		var w: WeaponDef = p.weapon
		if w.action_point_cost <= 0 or remaining_ap <= 0:
			continue
		var swings := floori(remaining_ap / w.action_point_cost)
		if swings <= 0:
			continue
		remaining_ap -= swings * w.action_point_cost
		var mean_dmg: float = (w.damage_min + w.damage_max) / 2.0
		var hit := clampf((combatant.stats.hit_chance + w.hit_bonus) / 100.0, 0.05, 0.95)
		total += mean_dmg * float(swings) * hit
	return total

## EHP: HP × avoidance_factor × armor_factor.
static func _effective_hp(combatant: Combatant, armor_k: float) -> float:
	var s := combatant.stats
	# Best parry bonus from own weapons (defender uses their own weapon to parry)
	var best_parry_bonus := 0
	for p in combatant.attack_profiles:
		if p.weapon.parry_bonus > best_parry_bonus:
			best_parry_bonus = p.weapon.parry_bonus
	# Sequential avoidance rolls matching HitRules: dodge first, then parry
	var effective_parry := clampf(float(s.parry + best_parry_bonus) / 100.0, 0.0, 0.95)
	var dodge_pct       := clampf(float(s.dodge) / 100.0, 0.0, 0.95)
	var p_avoid := clampf(dodge_pct + effective_parry * (1.0 - dodge_pct), 0.0, 0.95)
	var avoidance_factor := 1.0 / (1.0 - p_avoid)
	# Armor: (armor + K) / K — mirrors the hit_rules mitigation formula
	var armor_factor := (float(s.armor) + armor_k) / armor_k
	return float(s.max_hp) * avoidance_factor * armor_factor

## --- Old curve-based scoring (backward compat) ----------------------------

static func compute_curves(combatant: Combatant) -> int:
	_ensure_params()
	var s := combatant.stats
	var score: float = 0.0
	score += _apply_curve("max_hp", float(s.max_hp))
	score += _apply_curve("max_mp", float(s.max_mp))
	score += _apply_curve("max_action_points", float(s.max_action_points))
	score += _apply_curve("hit_chance", float(s.hit_chance))
	score += _apply_curve("dodge", float(s.dodge))
	score += _apply_curve("parry", float(s.parry))
	score += _apply_curve("armor", float(s.armor))
	score += _apply_curve("offensive_value", _total_dpr(combatant))
	return int(round(score))

static func _apply_curve(stat_name: String, value: float) -> float:
	if not _params.has(stat_name):
		return value
	var p: Dictionary = _params[stat_name]
	return curve(value, float(p.get("scale", 1.0)), float(p.get("midpoint", 1.0)), float(p.get("steepness", 1.0)))

## --- Loading --------------------------------------------------------------

static func _ensure_cost_table() -> void:
	if not _cost_table.is_empty():
		return
	_cost_table = _load_json(COST_TABLE_PATH, "cost table")

static func _ensure_params() -> void:
	if not _params.is_empty():
		return
	_params = _load_json(WEIGHTS_PATH, "score weights")

static func _load_json(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("%s not found at %s — using defaults" % [label, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open %s — using defaults" % label)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("%s JSON is not an object — using defaults" % label)
		return {}
	return parsed as Dictionary

## Force reload from disk (used by calibrator tools).
static func reload() -> void:
	_cost_table = _load_json(COST_TABLE_PATH, "cost table")
	_params = _load_json(WEIGHTS_PATH, "score weights")
