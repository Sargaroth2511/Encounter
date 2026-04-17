## Pure turn-order computation.
##
## Initiative order is determined once per round: higher max_action_points
## acts first, ties broken by combatant id for determinism. During the
## round the engine rotates actors through this queue, skipping any who
## have no remaining action points. See CombatEngine for the rotation.
class_name TurnOrder
extends RefCounted

static func order_for_round(combatants: Array[Combatant]) -> Array[Combatant]:
	var living: Array[Combatant] = []
	for c in combatants:
		if c.is_alive():
			living.append(c)
	living.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.stats.max_action_points != b.stats.max_action_points:
			return a.stats.max_action_points > b.stats.max_action_points
		return String(a.id) < String(b.id))
	return living
