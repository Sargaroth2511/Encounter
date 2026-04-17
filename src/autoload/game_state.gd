## Global, save-able game state.
##
## Holds data, not logic. Combat rules go in src/core/rules/, not here.
extends Node

var party: Array = []
var gold: int = 0
var current_scenario_id: StringName = &""
var flags: Dictionary = {}

func reset() -> void:
	party.clear()
	gold = 0
	current_scenario_id = &""
	flags.clear()
