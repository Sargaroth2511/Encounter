## An action submitted to the combat engine by a player or AI controller.
##
## Actions are intents; the engine decides their effects and emits events.
## AP cost is derived by the engine from the action type + referenced weapon
## or ability, not carried on the action itself — keeping the action a pure
## intent declaration.
class_name CombatAction
extends RefCounted

enum Type {
	ATTACK,
	ABILITY,
	DEFEND,
	ITEM,
	FLEE,
	END_TURN,
}

var actor_id: StringName
var type: Type
var target_ids: Array[StringName] = []
var ability_id: StringName = &""
## Which attack profile to use on an ATTACK. Empty = engine picks the first
## affordable profile.
var profile_id: StringName = &""

func _init(
		actor_id_: StringName,
		type_: Type,
		target_ids_: Array[StringName] = [],
		ability_id_: StringName = &"",
		profile_id_: StringName = &"",
) -> void:
	actor_id = actor_id_
	type = type_
	target_ids = target_ids_
	ability_id = ability_id_
	profile_id = profile_id_

func type_name() -> String:
	return Type.keys()[type].to_lower()
