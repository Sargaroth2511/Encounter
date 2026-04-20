## Loads a scenario JSON file and builds a fresh CombatState from it.
##
## Scenarios live at `res://assets/data/scenarios/<id>.json` and list the
## combatants for a fight. Each entry is either:
##
##   (a) Inline — full stats declared in the scenario:
##       { "id": "aria", "display_name": "Aria", "side": "PARTY",
##         "stats": { "max_hp": 20, "hit_chance": 75, "armor": 10, ... },
##         "attack_profiles": [ { "id": "main_hand", "weapon": "shortsword" } ] }
##
##   (b) Creature reference — pulls base stats + profiles from enemies/:
##       { "creature": "goblin", "side": "FOES" }
##       Optional: "id" (default: creature id), "display_name", "stats"
##       (selective overrides only), "attack_profiles" (replaces list).
##
##   (c) Hero reference — pulls base stats + profiles from heroes/:
##       { "hero": "aria", "side": "PARTY" }
##       Same optional overrides as creature references.
##
## On any failure returns null and reports the reason via push_error.
class_name ScenarioLoader
extends RefCounted

# Same reason as EnemyLoader: explicit preload until project is re-imported.
const EnemyLoader   := preload("res://src/core/combat/enemy_loader.gd")
const EnemyDef      := preload("res://src/core/entities/enemy_def.gd")
const HeroLoader    := preload("res://src/core/combat/hero_loader.gd")
const HeroDef       := preload("res://src/core/entities/hero_def.gd")
const AttackProfile := preload("res://src/core/entities/attack_profile.gd")
const WeaponLoader  := preload("res://src/core/combat/weapon_loader.gd")

const SCENARIO_DIR: String = "res://assets/data/scenarios/"

static func load_scenario(scenario_id: String) -> CombatState:
	var path := SCENARIO_DIR + scenario_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Scenario not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open scenario: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Scenario %s is not a JSON object" % path)
		return null
	return _build(parsed as Dictionary, path)

static func _build(data: Dictionary, path: String) -> CombatState:
	var combatants_raw: Variant = data.get("combatants", [])
	if typeof(combatants_raw) != TYPE_ARRAY:
		push_error("Scenario %s: `combatants` must be an array" % path)
		return null
	var state := CombatState.new()
	for entry in combatants_raw:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("Scenario %s: each combatant must be an object" % path)
			return null
		if not _add_combatant(state, entry as Dictionary, path):
			return null
	return state

static func _add_combatant(state: CombatState, entry: Dictionary, path: String) -> bool:
	var side_str: String = str(entry.get("side", ""))
	var side: int
	match side_str:
		"PARTY": side = Combatant.Side.PARTY
		"FOES":  side = Combatant.Side.FOES
		_:
			push_error("Scenario %s: combatant has invalid side %s (use PARTY or FOES)" % [path, side_str])
			return false

	var id: String
	var display_name: String
	var stats: Stats
	var profiles: Array[AttackProfile] = []

	if entry.has("hero"):
		var hero_id: String = str(entry["hero"])
		var def: HeroDef = HeroLoader.load_hero(hero_id)
		if def == null:
			push_error("Scenario %s: could not load hero '%s'" % [path, hero_id])
			return false
		id           = str(entry.get("id", def.hero_id))
		display_name = str(entry.get("display_name", def.display_name))
		var overrides_raw: Variant = entry.get("stats", {})
		if typeof(overrides_raw) != TYPE_DICTIONARY:
			push_error("Scenario %s: hero %s `stats` overrides must be an object" % [path, id])
			return false
		var overrides: Dictionary = overrides_raw
		stats = def.base_stats.with_overrides(overrides) if not overrides.is_empty() \
				else def.base_stats.duplicate_stats()
		if entry.has("attack_profiles"):
			if not _parse_profiles(entry["attack_profiles"], path, id, profiles):
				return false
		else:
			profiles = def.attack_profiles.duplicate()
	elif entry.has("creature"):
		var creature_id: String = str(entry["creature"])
		var def: EnemyDef = EnemyLoader.load_enemy(creature_id)
		if def == null:
			push_error("Scenario %s: could not load creature '%s'" % [path, creature_id])
			return false
		id           = str(entry.get("id", def.enemy_id))
		display_name = str(entry.get("display_name", def.display_name))
		var overrides_raw: Variant = entry.get("stats", {})
		if typeof(overrides_raw) != TYPE_DICTIONARY:
			push_error("Scenario %s: creature %s `stats` overrides must be an object" % [path, id])
			return false
		var overrides: Dictionary = overrides_raw
		stats = def.base_stats.with_overrides(overrides) if not overrides.is_empty() \
				else def.base_stats.duplicate_stats()
		if entry.has("attack_profiles"):
			if not _parse_profiles(entry["attack_profiles"], path, id, profiles):
				return false
		else:
			profiles = def.attack_profiles.duplicate()
	else:
		id = str(entry.get("id", ""))
		if id == "":
			push_error("Scenario %s: inline combatant missing `id`" % path)
			return false
		display_name = str(entry.get("display_name", id))
		var stats_raw: Variant = entry.get("stats", {})
		if typeof(stats_raw) != TYPE_DICTIONARY:
			push_error("Scenario %s: combatant %s `stats` must be an object" % [path, id])
			return false
		stats = Stats.from_dict(stats_raw as Dictionary)
		if not _parse_profiles(entry.get("attack_profiles", []), path, id, profiles):
			return false

	var combatant := Combatant.new(StringName(id), display_name, side, stats)
	combatant.attack_profiles = profiles
	state.add_combatant(combatant)
	return true

## Populates `out` with parsed profiles and returns true on success. On any
## failure pushes an error and leaves `out` in a partially filled state; the
## caller is expected to abort on a false return.
static func _parse_profiles(raw: Variant, path: String, owner_id: String, out: Array[AttackProfile]) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		push_error("Scenario %s: combatant %s `attack_profiles` must be an array" % [path, owner_id])
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("Scenario %s: %s profile entry must be an object" % [path, owner_id])
			return false
		var weapon_id: String = str(entry.get("weapon", ""))
		if weapon_id == "":
			push_error("Scenario %s: %s profile missing `weapon`" % [path, owner_id])
			return false
		var weapon := WeaponLoader.load_weapon(weapon_id)
		if weapon == null:
			push_error("Scenario %s: %s could not load weapon '%s'" % [path, owner_id, weapon_id])
			return false
		var profile_id: String = str(entry.get("id", weapon_id))
		var display_name: String = str(entry.get("display_name", weapon.display_name))
		out.append(AttackProfile.new(StringName(profile_id), display_name, weapon))
	return true
