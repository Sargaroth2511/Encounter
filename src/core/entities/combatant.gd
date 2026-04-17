## A participant in a fight. Runtime state, not content definition.
##
## Content (enemy templates, hero classes, weapon defs) lives as Resources /
## JSON in assets/data/. A Combatant is produced by the combat setup code
## from that content and carries only live-fight state.
class_name Combatant
extends RefCounted

enum Side { PARTY, FOES }

var id: StringName
var display_name: String
var side: int  # Combatant.Side — int avoids GDScript inner-enum type-mismatch bug
var stats: Stats
var hp: int
var mp: int
var action_points: int
var statuses: Array[StringName] = []
## Attack sources (main hand, off hand, natural attacks). At least one
## profile is required to attack; combatants with an empty list can only
## use non-attack actions.
var attack_profiles: Array[AttackProfile] = []

func _init(id_: StringName, display_name_: String, side_: int, stats_: Stats) -> void:
	id = id_
	display_name = display_name_
	side = side_
	stats = stats_
	hp = stats_.max_hp
	mp = stats_.max_mp
	action_points = stats_.max_action_points

func is_alive() -> bool:
	return hp > 0

func apply_damage(amount: int) -> int:
	var before := hp
	hp = max(0, hp - amount)
	return before - hp

func apply_heal(amount: int) -> int:
	var before := hp
	hp = min(stats.max_hp, hp + amount)
	return hp - before

## Refill AP at the start of a round.
func refresh_action_points() -> void:
	action_points = stats.max_action_points

## Returns the profile with the given id, or null if absent.
func find_profile(profile_id: StringName) -> AttackProfile:
	for p in attack_profiles:
		if p.profile_id == profile_id:
			return p
	return null

## Cheapest AP cost among this combatant's attack profiles, or -1 if none.
## Used by the engine to decide when no affordable action remains.
func cheapest_attack_cost() -> int:
	var best := -1
	for p in attack_profiles:
		var c := p.weapon.action_point_cost
		if best < 0 or c < best:
			best = c
	return best
