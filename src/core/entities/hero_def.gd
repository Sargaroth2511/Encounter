## Immutable content template for a hero/player-character archetype.
##
## "What Aria is" — base stats, weapons, and display info loaded from
## `assets/data/heroes/<id>.json`. Produced by HeroLoader and consumed by
## ScenarioLoader.
##
## Mirrors EnemyDef intentionally; heroes and foes share the same Combatant
## pipeline at fight time.
class_name HeroDef
extends RefCounted

var hero_id: StringName = &""
var display_name: String = ""
var base_stats: Stats = null
var attack_profiles: Array[AttackProfile] = []
