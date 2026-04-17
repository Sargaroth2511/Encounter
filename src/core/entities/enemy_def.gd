## Immutable content template for a foe archetype.
##
## "What a goblin is" — base stats, weapons, and display info loaded from
## `assets/data/enemies/<id>.json`. Produced by EnemyLoader and consumed by
## ScenarioLoader (and later by ProceduralEncounterFactory / the pool picker).
##
## Not to be confused with Combatant, which is live fight state derived from
## an EnemyDef at encounter setup time.
class_name EnemyDef
extends RefCounted

var enemy_id: StringName = &""
var display_name: String = ""
var base_stats: Stats = null
var attack_profiles: Array[AttackProfile] = []
