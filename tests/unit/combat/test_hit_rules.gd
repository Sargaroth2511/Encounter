## Unit tests for HitRules — verifies each branch of the hit → dodge →
## parry → armor pipeline resolves correctly with deterministic numbers.
##
## Run via: godot --headless --script tests/unit/combat/test_hit_rules.gd
extends SceneTree

const WeaponDef     := preload("res://src/core/entities/weapon_def.gd")
const AttackProfile := preload("res://src/core/entities/attack_profile.gd")

func _initialize() -> void:
	_test_certain_hit_deals_damage()
	_test_guaranteed_miss()
	_test_guaranteed_dodge()
	_test_guaranteed_parry()
	_test_unparryable_weapon_ignores_parry()
	_test_armor_mitigates_percent()
	print("[OK] hit_rules")
	quit()

func _weapon(ap: int, dmg_min: int, dmg_max: int,
		hit_bonus: int = 0, parry_bonus: int = 0,
		parryable: bool = true) -> WeaponDef:
	var w := WeaponDef.new()
	w.weapon_id = &"test_weapon"
	w.display_name = "Test Weapon"
	w.weapon_kind = "test"
	w.damage_type = "slashing"
	w.damage_min = dmg_min; w.damage_max = dmg_max
	w.action_point_cost = ap
	w.hit_bonus = hit_bonus
	w.parry_bonus = parry_bonus
	w.parryable = parryable
	return w

func _combatant(hit: int, dodge: int, parry: int, armor: int, weapon: WeaponDef) -> Combatant:
	var s := Stats.new()
	s.max_hp = 10; s.max_action_points = 3
	s.hit_chance = hit; s.dodge = dodge; s.parry = parry; s.armor = armor
	var c := Combatant.new(&"x", "X", Combatant.Side.PARTY, s)
	c.attack_profiles = [AttackProfile.new(&"main", "Main", weapon)]
	return c

func _test_certain_hit_deals_damage() -> void:
	# Hit chance clamps to 95% max, so loop seeds until we observe a HIT.
	var w := _weapon(2, 5, 5)
	var atk := _combatant(100, 0, 0, 0, w)
	var def := _combatant(50, 0, 0, 0, w)
	var r: Dictionary = _find_outcome(atk, w, def, HitRules.Outcome.HIT)
	assert(not r.is_empty(), "never observed a HIT at 95% hit chance across 200 seeds")
	assert(r["damage"] == 5, "expected 5 damage, got %d" % r["damage"])

func _test_guaranteed_miss() -> void:
	var w := _weapon(2, 5, 5)
	# Hit chance is clamped at HIT_MIN (5%); use enough seeds to find a miss.
	var atk := _combatant(0, 0, 0, 0, w)   # → clamped to 5
	var def := _combatant(50, 0, 0, 0, w)
	var saw_miss := false
	for seed in range(1, 200):
		var r := HitRules.resolve(atk, w, def, SeededRng.new(seed))
		if r["outcome"] == HitRules.Outcome.MISS:
			saw_miss = true
			break
	assert(saw_miss, "never observed a MISS at 5% hit chance across 200 seeds")

func _test_guaranteed_dodge() -> void:
	var w := _weapon(2, 5, 5)
	var atk := _combatant(100, 0, 0, 0, w)
	var def := _combatant(100, 95, 0, 0, w)  # max allowed dodge
	var r: Dictionary = _find_outcome(atk, w, def, HitRules.Outcome.DODGED)
	assert(not r.is_empty(), "never observed a DODGE")

func _test_guaranteed_parry() -> void:
	var w := _weapon(2, 5, 5, 0, 95)  # weapon grants 95 parry to wielder
	var atk := _combatant(100, 0, 0, 0, w)
	var def := _combatant(100, 0, 0, 0, w)
	var r: Dictionary = _find_outcome(atk, w, def, HitRules.Outcome.PARRIED)
	assert(not r.is_empty(), "never observed a PARRY")

func _test_unparryable_weapon_ignores_parry() -> void:
	var arrow := _weapon(2, 5, 5, 0, 0, false)        # not parryable
	var parry_weapon := _weapon(2, 5, 5, 0, 95, true) # defender holds it
	var atk := _combatant(100, 0, 0, 0, arrow)
	var def := _combatant(100, 0, 0, 0, parry_weapon)
	# Parry must never fire for an unparryable weapon. Sweep seeds and
	# confirm outcomes are only HIT, MISS, or DODGED (dodge is 0 here).
	var saw_hit := false
	for seed in range(1, 200):
		var r := HitRules.resolve(atk, arrow, def, SeededRng.new(seed))
		assert(r["outcome"] != HitRules.Outcome.PARRIED,
				"unparryable weapon was parried at seed %d" % seed)
		if r["outcome"] == HitRules.Outcome.HIT:
			saw_hit = true
	assert(saw_hit, "never observed any HIT for unparryable weapon")

func _test_armor_mitigates_percent() -> void:
	var w := _weapon(2, 10, 10)
	var atk := _combatant(100, 0, 0, 0, w)
	var def := _combatant(100, 0, 0, 50, w)   # 50% armor
	var r: Dictionary = _find_outcome(atk, w, def, HitRules.Outcome.HIT)
	assert(not r.is_empty(), "never observed a HIT")
	assert(r["raw_damage"] == 10, "raw should be 10, got %d" % r["raw_damage"])
	assert(r["damage"] == 5, "expected 5 after 50%% armor, got %d" % r["damage"])

## Sweeps seeds 1..200 looking for the requested outcome. Returns the result
## dict, or an empty dict if no seed produced it. Used for tests where the
## pipeline clamps probabilities below 100%.
func _find_outcome(atk: Combatant, w: WeaponDef, def: Combatant, wanted: int) -> Dictionary:
	for seed in range(1, 200):
		var r := HitRules.resolve(atk, w, def, SeededRng.new(seed))
		if r["outcome"] == wanted:
			return r
	return {}
