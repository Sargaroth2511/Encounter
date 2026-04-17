## Snapshot of the whole fight at a moment in time.
##
## Owned by CombatEngine. External subscribers should treat it as read-only.
class_name CombatState
extends RefCounted

var scenario_id: StringName = &""
var round_number: int = 0
var turn_number: int = 0
var tick: int = 0
var combatants: Array[Combatant] = []

func add_combatant(c: Combatant) -> void:
	combatants.append(c)

func find(id: StringName) -> Combatant:
	for c in combatants:
		if c.id == id:
			return c
	return null

func living_on_side(side: Combatant.Side) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c in combatants:
		if c.side == side and c.is_alive():
			out.append(c)
	return out

func is_side_wiped(side: Combatant.Side) -> bool:
	return living_on_side(side).is_empty()
