## One way a combatant can attack.
##
## A combatant may have several profiles: "main_hand" + "off_hand" for a
## dual-wielder, or "bite" + "claws" + "tail" for a beast. Each profile
## references a WeaponDef that supplies damage, AP cost, and modifiers.
##
## Profile ids are local to the combatant (two combatants can both have a
## "main_hand" profile pointing at different weapons). The id is emitted
## in events so logs and UI can describe which limb swung.
class_name AttackProfile
extends RefCounted

var profile_id: StringName
var display_name: String
var weapon: WeaponDef

func _init(profile_id_: StringName, display_name_: String, weapon_: WeaponDef) -> void:
	profile_id = profile_id_
	display_name = display_name_
	weapon = weapon_
