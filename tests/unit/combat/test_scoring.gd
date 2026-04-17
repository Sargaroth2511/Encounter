## Sanity tests for Scoring — not calibration (that's what combat_batch is
## for). Verifies scores respond to the inputs in the expected direction.
##
## Run via: godot --headless --script tests/unit/combat/test_scoring.gd
extends SceneTree

const WeaponDef     := preload("res://src/core/entities/weapon_def.gd")
const AttackProfile := preload("res://src/core/entities/attack_profile.gd")

func _initialize() -> void:
	_test_score_is_positive()
	_test_better_weapon_scores_higher()
	_test_more_hp_scores_higher()
	print("[OK] scoring")
	quit()

func _build(hp: int, hit: int, weapon: WeaponDef) -> Combatant:
	var s := Stats.new()
	s.max_hp = hp
	s.max_action_points = 3
	s.hit_chance = hit
	s.dodge = 5
	s.parry = 0
	s.armor = 5
	var c := Combatant.new(&"c", "C", Combatant.Side.PARTY, s)
	c.attack_profiles = [AttackProfile.new(&"main", "Main", weapon)]
	return c

func _weapon(dmg_min: int, dmg_max: int) -> WeaponDef:
	var w := WeaponDef.new()
	w.weapon_id = &"w"
	w.weapon_kind = "sword"
	w.damage_type = "slashing"
	w.damage_min = dmg_min; w.damage_max = dmg_max
	w.action_point_cost = 2
	return w

func _test_score_is_positive() -> void:
	var c := _build(20, 70, _weapon(3, 5))
	var score := Scoring.compute(c)
	assert(score > 0, "expected positive score, got %d" % score)

func _test_better_weapon_scores_higher() -> void:
	var weak := _build(20, 70, _weapon(2, 3))
	var strong := _build(20, 70, _weapon(6, 9))
	assert(Scoring.compute(strong) > Scoring.compute(weak),
			"strong weapon should outscore weak one")

func _test_more_hp_scores_higher() -> void:
	var frail := _build(10, 70, _weapon(3, 5))
	var tank  := _build(40, 70, _weapon(3, 5))
	assert(Scoring.compute(tank) > Scoring.compute(frail),
			"more HP should score higher")
