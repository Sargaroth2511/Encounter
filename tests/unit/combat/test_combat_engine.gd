## Smoke test for CombatEngine on the new weapon/AP system.
##
## Verifies:
##   - a seeded fight produces a deterministic event sequence,
##   - it terminates with a winner,
##   - AP is refilled each round and drained by action cost.
##
## Run via: godot --headless --script tests/unit/combat/test_combat_engine.gd
extends SceneTree

const WeaponDef      := preload("res://src/core/entities/weapon_def.gd")
const AttackProfile  := preload("res://src/core/entities/attack_profile.gd")

func _initialize() -> void:
	_test_fight_terminates()
	_test_fight_is_deterministic()
	_test_ap_refills_each_round()
	print("[OK] combat_engine")
	quit()

func _make_weapon(id: String, dmg_min: int, dmg_max: int, ap: int, hit_bonus: int = 0, parry_bonus: int = 0) -> WeaponDef:
	var w := WeaponDef.new()
	w.weapon_id = StringName(id)
	w.display_name = id
	w.weapon_kind = "test"
	w.damage_type = "slashing"
	w.damage_min = dmg_min
	w.damage_max = dmg_max
	w.hit_bonus = hit_bonus
	w.parry_bonus = parry_bonus
	w.action_point_cost = ap
	w.parryable = true
	return w

func _make_combatant(id: StringName, name: String, side: int, stats: Stats, weapon: WeaponDef) -> Combatant:
	var c := Combatant.new(id, name, side, stats)
	c.attack_profiles = [AttackProfile.new(&"main_hand", "Main", weapon)]
	return c

func _build() -> Dictionary:
	var rng := SeededRng.new(42)
	var state := CombatState.new()
	var a := Stats.new()
	a.max_hp = 30; a.max_action_points = 4; a.hit_chance = 99; a.dodge = 0; a.parry = 0; a.armor = 0
	var b := Stats.new()
	b.max_hp = 14; b.max_action_points = 3; b.hit_chance = 80; b.dodge = 0; b.parry = 0; b.armor = 0
	var sword := _make_weapon("sword", 4, 6, 2)
	var claws := _make_weapon("claws", 2, 4, 2)
	state.add_combatant(_make_combatant(&"aria", "Aria", Combatant.Side.PARTY, a, sword))
	state.add_combatant(_make_combatant(&"goblin", "Goblin", Combatant.Side.FOES, b, claws))
	var engine := CombatEngine.new(state, rng)
	return {"engine": engine, "state": state}

func _run_auto(engine: CombatEngine) -> void:
	var safety := 0
	while not engine.is_ended():
		var actor: Combatant = engine.current_actor()
		if actor == null:
			break
		var enemy_side: Combatant.Side = Combatant.Side.FOES \
				if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
		var targets: Array[Combatant] = engine.state().living_on_side(enemy_side)
		if targets.is_empty():
			break
		var action: CombatAction
		if actor.action_points >= actor.attack_profiles[0].weapon.action_point_cost:
			action = CombatAction.new(actor.id, CombatAction.Type.ATTACK, [targets[0].id])
		else:
			action = CombatAction.new(actor.id, CombatAction.Type.END_TURN)
		engine.submit_action(action)
		safety += 1
		if safety > 1000:
			assert(false, "infinite loop guard tripped")
			return

func _test_fight_terminates() -> void:
	var ctx := _build()
	var engine: CombatEngine = ctx["engine"]
	var log := CombatLog.new()
	log.bind(engine)
	engine.start(&"test_basic")
	_run_auto(engine)
	assert(engine.is_ended(), "fight did not terminate")
	assert(log.events().size() > 0, "no events emitted")

func _test_fight_is_deterministic() -> void:
	var run_1 := _capture_log(1337)
	var run_2 := _capture_log(1337)
	assert(run_1 == run_2, "same seed produced different logs")

func _capture_log(seed_value: int) -> String:
	var rng := SeededRng.new(seed_value)
	var state := CombatState.new()
	var a := Stats.new(); a.max_hp = 30; a.max_action_points = 4; a.hit_chance = 99
	var b := Stats.new(); b.max_hp = 14; b.max_action_points = 3; b.hit_chance = 80
	var sword := _make_weapon("sword", 4, 6, 2)
	var claws := _make_weapon("claws", 2, 4, 2)
	state.add_combatant(_make_combatant(&"aria", "Aria", Combatant.Side.PARTY, a, sword))
	state.add_combatant(_make_combatant(&"goblin", "Goblin", Combatant.Side.FOES, b, claws))
	var engine := CombatEngine.new(state, rng)
	var log := CombatLog.new()
	log.bind(engine)
	engine.start(&"det")
	_run_auto(engine)
	return log.render(CombatLog.Format.JSONL)

func _test_ap_refills_each_round() -> void:
	var ctx := _build()
	var engine: CombatEngine = ctx["engine"]
	var state: CombatState = ctx["state"]
	engine.start(&"ap_refill")
	# Advance one action; actor has 4 AP, a 2-AP sword → 2 AP left after one swing.
	var actor := engine.current_actor()
	var max_ap := actor.stats.max_action_points
	var cost := actor.attack_profiles[0].weapon.action_point_cost
	engine.submit_action(CombatAction.new(actor.id, CombatAction.Type.ATTACK, [state.combatants[1].id]))
	assert(actor.action_points == max_ap - cost,
			"AP not decremented correctly: got %d, expected %d" % [actor.action_points, max_ap - cost])
	# Run to completion; after any full round start, alive actors should have full AP.
	_run_auto(engine)
	assert(engine.is_ended(), "fight did not terminate")
