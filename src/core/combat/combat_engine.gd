## The combat simulation.
##
## Pure logic. Does not extend Node, does not touch the scene tree, does not
## use real-time timers or unseeded randomness. Runs identically headless
## (CLI / tests) and inside the game.
##
## Flow:
##   1. Caller builds CombatState + SeededRng, passes them in.
##   2. Caller calls start(), then submit_action() for each AP expenditure.
##   3. Engine emits CombatEvents via `event_emitted`. Subscribers (log, UI)
##      render them.
##
## Turn model (schema 2.0):
##   - At round start every living combatant gets `max_action_points` AP.
##   - Initiative queue = combatants ordered by TurnOrder (by max AP).
##   - Each turn the frontmost actor submits one action; AP is deducted
##     from the action's cost and the actor rotates to the back of the
##     queue if they still have >= MIN_TURN_AP AP. Round ends when queue
##     is empty.
class_name CombatEngine
extends RefCounted

signal event_emitted(event: CombatEvent)

## Minimum AP needed to stay in the initiative queue (enough to defend or
## end-turn explicitly). Below this, the actor drops out of the round.
const MIN_TURN_AP: int = 1

## AP cost of actions whose cost isn't implied by a weapon or ability.
const DEFEND_AP_COST: int = 1
const END_TURN_AP_COST: int = 0

var _state: CombatState
var _rng: SeededRng
var _turn_queue: Array[Combatant] = []
var _ended: bool = false

func _init(state: CombatState, rng: SeededRng) -> void:
	_state = state
	_rng = rng

func state() -> CombatState:
	return _state

func is_ended() -> bool:
	return _ended

func start(scenario_id: StringName = &"") -> void:
	_state.scenario_id = scenario_id
	_emit(CombatEvent.Type.COMBAT_STARTED, {
		"seed": _rng.seed(),
		"scenario_id": String(scenario_id),
		"schema_version": CombatEvent.SCHEMA_VERSION,
		"participants": _participants_summary(),
	})
	_begin_round()

func current_actor() -> Combatant:
	if _ended or _turn_queue.is_empty():
		return null
	return _turn_queue[0]

func submit_action(action: CombatAction) -> void:
	assert(not _ended, "combat already ended")
	var actor := current_actor()
	assert(actor != null and actor.id == action.actor_id, "action from wrong actor")

	var ap_cost := _compute_ap_cost(actor, action)
	assert(actor.action_points >= ap_cost,
			"actor %s cannot afford %s (%d AP, have %d)"
			% [actor.id, action.type_name(), ap_cost, actor.action_points])

	_emit(CombatEvent.Type.ACTION_DECLARED, {
		"actor_id": actor.id,
		"action_type": action.type_name(),
		"target_ids": action.target_ids,
		"ability_id": String(action.ability_id),
		"profile_id": String(action.profile_id),
		"ap_cost": ap_cost,
	})

	match action.type:
		CombatAction.Type.ATTACK:
			_resolve_attack(actor, action)
		CombatAction.Type.DEFEND:
			pass  # placeholder — hook buffs/mitigation here
		CombatAction.Type.END_TURN:
			pass
		_:
			push_warning("action type not implemented: %s" % action.type_name())

	_spend_ap(actor, ap_cost, action.type_name())
	_emit(CombatEvent.Type.TURN_ENDED, {"actor_id": actor.id})
	_turn_queue.pop_front()

	if _check_end():
		return

	# Re-queue the actor if they still have resources and chose not to end turn.
	if action.type != CombatAction.Type.END_TURN \
			and actor.is_alive() \
			and actor.action_points >= MIN_TURN_AP:
		_turn_queue.append(actor)

	if _turn_queue.is_empty():
		_end_round()
		if not _ended:
			_begin_round()
	else:
		_announce_turn()

# --- internals ---------------------------------------------------------

func _compute_ap_cost(actor: Combatant, action: CombatAction) -> int:
	match action.type:
		CombatAction.Type.ATTACK:
			var profile := _select_profile(actor, action.profile_id)
			return profile.weapon.action_point_cost if profile != null else 0
		CombatAction.Type.DEFEND:
			return DEFEND_AP_COST
		CombatAction.Type.END_TURN:
			return END_TURN_AP_COST
		_:
			return 1

func _select_profile(actor: Combatant, profile_id: StringName) -> AttackProfile:
	if profile_id != &"":
		return actor.find_profile(profile_id)
	# Default: cheapest affordable profile, ties by original declaration order.
	var best: AttackProfile = null
	for p in actor.attack_profiles:
		if p.weapon.action_point_cost > actor.action_points:
			continue
		if best == null or p.weapon.action_point_cost < best.weapon.action_point_cost:
			best = p
	if best == null and not actor.attack_profiles.is_empty():
		best = actor.attack_profiles[0]
	return best

func _resolve_attack(actor: Combatant, action: CombatAction) -> void:
	if action.target_ids.is_empty():
		return
	var target := _state.find(action.target_ids[0])
	if target == null or not target.is_alive():
		return
	var profile := _select_profile(actor, action.profile_id)
	if profile == null:
		push_warning("%s tried to attack without an attack profile" % actor.id)
		return
	var weapon := profile.weapon
	var r := HitRules.resolve(actor, weapon, target, _rng)
	var outcome: int = r["outcome"]
	if outcome != HitRules.Outcome.HIT:
		_emit(CombatEvent.Type.ATTACK_MISSED, {
			"source_id": actor.id,
			"target_id": target.id,
			"profile_id": String(profile.profile_id),
			"weapon_id": String(weapon.weapon_id),
			"outcome": HitRules.outcome_name(outcome),
			"hit_chance": r["hit_chance"],
			"dodge_chance": r["dodge_chance"],
			"parry_chance": r["parry_chance"],
			"parry_weapon_id": r["parry_weapon_id"],
		})
		return
	var before := target.hp
	var applied := target.apply_damage(r["damage"])
	_emit(CombatEvent.Type.DAMAGE_DEALT, {
		"source_id": actor.id,
		"target_id": target.id,
		"profile_id": String(profile.profile_id),
		"weapon_id": String(weapon.weapon_id),
		"amount": applied,
		"raw_damage": r["raw_damage"],
		"armor_pct": r["armor_pct"],
		"damage_type": weapon.damage_type,
		"hp_before": before,
		"hp_after": target.hp,
	})
	if not target.is_alive():
		_emit(CombatEvent.Type.COMBATANT_FELL, {"combatant_id": target.id})

func _spend_ap(actor: Combatant, cost: int, reason: String) -> void:
	if cost <= 0:
		return
	var before := actor.action_points
	actor.action_points = max(0, actor.action_points - cost)
	_emit(CombatEvent.Type.ACTION_POINTS_CHANGED, {
		"actor_id": actor.id,
		"before": before,
		"after": actor.action_points,
		"delta": -cost,
		"reason": reason,
	})

func _begin_round() -> void:
	_state.round_number += 1
	_state.turn_number = 0
	for c in _state.combatants:
		if c.is_alive():
			c.refresh_action_points()
	_emit(CombatEvent.Type.ROUND_STARTED, {})
	_turn_queue = TurnOrder.order_for_round(_state.combatants)
	# Drop anyone who can't even afford the minimum-turn AP.
	var affordable: Array[Combatant] = []
	for c in _turn_queue:
		if c.action_points >= MIN_TURN_AP:
			affordable.append(c)
	_turn_queue = affordable
	if _turn_queue.is_empty():
		_finish(&"draw", &"stalemate_no_ap")
		return
	_announce_turn()

func _announce_turn() -> void:
	_state.turn_number += 1
	_emit(CombatEvent.Type.TURN_STARTED, {"actor_id": _turn_queue[0].id})

func _end_round() -> void:
	_emit(CombatEvent.Type.ROUND_ENDED, {})

func _check_end() -> bool:
	if _state.is_side_wiped(Combatant.Side.FOES):
		_finish(&"party", &"all_foes_down")
		return true
	if _state.is_side_wiped(Combatant.Side.PARTY):
		_finish(&"foes", &"all_party_down")
		return true
	return false

func _finish(winner: StringName, reason: StringName) -> void:
	_ended = true
	_emit(CombatEvent.Type.COMBAT_ENDED, {
		"winner": String(winner),
		"reason": String(reason),
		"duration_rounds": _state.round_number,
		"survivors": _survivors_summary(),
	})

func _emit(type: CombatEvent.Type, payload: Dictionary) -> void:
	_state.tick += 1
	var e := CombatEvent.new(type, payload)
	e.tick = _state.tick
	e.round_number = _state.round_number
	e.turn_number = _state.turn_number
	event_emitted.emit(e)

func _participants_summary() -> Array:
	var out: Array = []
	for c in _state.combatants:
		out.append({
			"id": String(c.id),
			"name": c.display_name,
			"side": Combatant.Side.keys()[c.side].to_lower(),
			"hp": c.hp,
			"max_hp": c.stats.max_hp,
			"max_action_points": c.stats.max_action_points,
			"score": Scoring.compute(c),
		})
	return out

func _survivors_summary() -> Array:
	var out: Array = []
	for c in _state.combatants:
		if c.is_alive():
			out.append({
				"id": String(c.id),
				"side": Combatant.Side.keys()[c.side].to_lower(),
				"hp": c.hp,
				"max_hp": c.stats.max_hp,
			})
	return out
