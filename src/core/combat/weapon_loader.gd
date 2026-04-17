## Loads a WeaponDef from `res://assets/data/weapons/<id>.json`.
##
## Returns null (+ push_error) on missing file, unreadable file, or bad JSON.
## Results are cached for the lifetime of the loader to avoid re-parsing
## shared weapons across many combatants in a batch run.
class_name WeaponLoader
extends RefCounted

const WeaponDef := preload("res://src/core/entities/weapon_def.gd")

const WEAPON_DIR: String = "res://assets/data/weapons/"

static var _cache: Dictionary = {}

static func load_weapon(weapon_id: String) -> WeaponDef:
	if _cache.has(weapon_id):
		return _cache[weapon_id]
	var path := WEAPON_DIR + weapon_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Weapon def not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open weapon def: %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Weapon def %s is not a JSON object" % path)
		return null
	var w := WeaponDef.from_dict(parsed as Dictionary, weapon_id)
	_cache[weapon_id] = w
	return w

static func clear_cache() -> void:
	_cache.clear()
