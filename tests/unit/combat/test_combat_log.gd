## Verifies CombatLog renders both text and JSONL formats without crashing
## and includes the expected structural markers.
extends SceneTree

const WeaponDef      := preload("res://src/core/entities/weapon_def.gd")
const AttackProfile  := preload("res://src/core/entities/attack_profile.gd")

func _initialize() -> void:
	var rng := SeededRng.new(7)
	var state := CombatState.new()
	var s := Stats.new(); s.max_hp = 20; s.max_action_points = 4; s.hit_chance = 99
	var t := Stats.new(); t.max_hp = 10; t.max_action_points = 3; t.hit_chance = 80
	var sword := _weapon("sword", 5, 7, 2)
	var claws := _weapon("claws", 2, 3, 2)
	state.add_combatant(_cmb(&"p", "Hero", Combatant.Side.PARTY, s, sword))
	state.add_combatant(_cmb(&"f", "Foe",  Combatant.Side.FOES,  t, claws))
	var engine := CombatEngine.new(state, rng)
	var log := CombatLog.new()
	log.bind(engine)
	engine.start(&"t")
	var safety := 0
	while not engine.is_ended():
		var actor: Combatant = engine.current_actor()
		var enemy_side: Combatant.Side = Combatant.Side.FOES \
				if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
		var targets: Array[Combatant] = engine.state().living_on_side(enemy_side)
		if targets.is_empty(): break
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
	var text := log.render(CombatLog.Format.TEXT)
	var jsonl := log.render(CombatLog.Format.JSONL)
	assert("COMBAT start" in text, "text log missing start marker")
	assert("COMBAT end" in text, "text log missing end marker")
	assert("AP" in text, "text log missing AP tracking")
	assert("\"type\":\"combat_started\"" in jsonl, "jsonl log missing combat_started")
	assert("\"type\":\"combat_ended\"" in jsonl, "jsonl log missing combat_ended")
	assert("\"type\":\"action_points_changed\"" in jsonl, "jsonl log missing action_points_changed")
	print("[OK] combat_log")
	quit()

func _weapon(id: String, dmg_min: int, dmg_max: int, ap: int) -> WeaponDef:
	var w := WeaponDef.new()
	w.weapon_id = StringName(id); w.display_name = id
	w.weapon_kind = "test"; w.damage_type = "slashing"
	w.damage_min = dmg_min; w.damage_max = dmg_max
	w.action_point_cost = ap
	return w

func _cmb(id: StringName, name: String, side: int, stats: Stats, weapon: WeaponDef) -> Combatant:
	var c := Combatant.new(id, name, side, stats)
	c.attack_profiles = [AttackProfile.new(&"main_hand", "Main", weapon)]
	return c
