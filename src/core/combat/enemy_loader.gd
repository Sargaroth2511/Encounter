## Loads an enemy archetype from `res://assets/data/enemies/<id>.json`.
##
## Returns null (+ push_error) on missing file, unreadable file, bad JSON,
## or unresolvable weapon reference.
class_name EnemyLoader
extends RefCounted

# Explicit preload required because these were added outside Godot's import
# step and therefore have no .uid — their class_name is not in the global
# registry until the project is re-imported.
const EnemyDef      := preload("res://src/core/entities/enemy_def.gd")
const AttackProfile := preload("res://src/core/entities/attack_profile.gd")
const WeaponLoader  := preload("res://src/core/combat/weapon_loader.gd")

const ENEMY_DIR: String = "res://assets/data/enemies/"

static func load_enemy(enemy_id: String) -> EnemyDef:
	var path := ENEMY_DIR + enemy_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Enemy def not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open enemy def: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Enemy def %s is not a JSON object" % path)
		return null
	return _build(parsed as Dictionary, enemy_id, path)

static func _build(data: Dictionary, enemy_id: String, path: String) -> EnemyDef:
	var stats_raw: Variant = data.get("stats", {})
	if typeof(stats_raw) != TYPE_DICTIONARY:
		push_error("Enemy def %s: `stats` must be an object" % path)
		return null
	var def := EnemyDef.new()
	def.enemy_id = StringName(enemy_id)
	def.display_name = str(data.get("display_name", enemy_id))
	def.base_stats = Stats.from_dict(stats_raw as Dictionary)
	var profiles: Array[AttackProfile] = []
	if not _load_profiles(data.get("attack_profiles", []), path, profiles):
		return null
	def.attack_profiles = profiles
	return def

## Populates `out` with parsed profiles and returns true on success. Each
## entry: { "id": "...", "display_name": "...", "weapon": "<weapon_id>" }.
## On any failure pushes an error and returns false.
static func _load_profiles(raw: Variant, path: String, out: Array[AttackProfile]) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		push_error("%s: `attack_profiles` must be an array" % path)
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("%s: each attack profile must be an object" % path)
			return false
		var weapon_id: String = str(entry.get("weapon", ""))
		if weapon_id == "":
			push_error("%s: attack profile missing `weapon`" % path)
			return false
		var weapon := WeaponLoader.load_weapon(weapon_id)
		if weapon == null:
			push_error("%s: could not load weapon '%s'" % [path, weapon_id])
			return false
		var profile_id: String = str(entry.get("id", weapon_id))
		var display_name: String = str(entry.get("display_name", weapon.display_name))
		out.append(AttackProfile.new(StringName(profile_id), display_name, weapon))
	return true
