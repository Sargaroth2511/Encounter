## Immutable content template for a weapon (or natural attack).
##
## Weapons carry their own damage roll, AP cost, and modifiers to the
## wielder's hit/parry. "Natural" attacks (goblin bite, wyvern tail) are
## just weapons tagged with `weapon_kind = "natural"` — the combat core
## does not distinguish between equipped and intrinsic armament.
##
## Loaded by WeaponLoader from `assets/data/weapons/<id>.json`.
class_name WeaponDef
extends RefCounted

var weapon_id: StringName = &""
var display_name: String = ""
var weapon_kind: String = "unarmed"        ## sword, dagger, bow, natural, etc.
var damage_type: String = "bludgeoning"    ## see DamageType hierarchy
var damage_min: int = 1
var damage_max: int = 2
var hit_bonus: int = 0                     ## added to wielder.hit_chance (%)
var parry_bonus: int = 0                   ## added to wielder.parry when wielded (%)
var action_point_cost: int = 2             ## AP spent per attack with this weapon
var parryable: bool = true                 ## can attacks with this weapon be parried?
## Weapon kinds that are allowed to parry attacks *from* this weapon. Empty =
## any melee kind can parry. A ranged weapon can still set parryable=false to
## disable parry entirely regardless of this list.
var parry_allowed_kinds: Array[String] = []

static func from_dict(data: Dictionary, weapon_id: String) -> WeaponDef:
	var w := WeaponDef.new()
	w.weapon_id         = StringName(weapon_id)
	w.display_name      = str(data.get("display_name", weapon_id))
	w.weapon_kind       = str(data.get("weapon_kind", w.weapon_kind))
	w.damage_type       = str(data.get("damage_type", w.damage_type))
	w.damage_min        = int(data.get("damage_min", w.damage_min))
	w.damage_max        = int(data.get("damage_max", w.damage_max))
	w.hit_bonus         = int(data.get("hit_bonus", w.hit_bonus))
	w.parry_bonus       = int(data.get("parry_bonus", w.parry_bonus))
	w.action_point_cost = int(data.get("action_point_cost", w.action_point_cost))
	w.parryable         = bool(data.get("parryable", w.parryable))
	var allowed_raw: Variant = data.get("parry_allowed_kinds", [])
	if typeof(allowed_raw) == TYPE_ARRAY:
		var allowed: Array[String] = []
		for k in allowed_raw:
			allowed.append(str(k))
		w.parry_allowed_kinds = allowed
	return w
