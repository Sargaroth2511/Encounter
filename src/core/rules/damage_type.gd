## Damage type hierarchy.
##
## Every damage type belongs to a root category:
##
##   physical  ← slashing, piercing, bludgeoning
##   magical   ← fire, ice, lightning, arcane
##
## Use DamageType.is_a(type, "physical") to check category membership.
## This will drive resistances, immunities, and body-part overrides once
## those systems exist.
class_name DamageType
extends RefCounted

## Maps each sub-type to its immediate parent. Root types are absent.
const PARENTS: Dictionary = {
	"slashing":    "physical",
	"piercing":    "physical",
	"bludgeoning": "physical",
	"fire":        "magical",
	"ice":         "magical",
	"lightning":   "magical",
	"arcane":      "magical",
}

## Returns the direct parent category of [type], or "" for root types
## ("physical", "magical") and unknown types.
static func parent_of(type: String) -> String:
	return PARENTS.get(type, "")

## Returns true if [subtype] is equal to or descends from [ancestor].
## Examples:
##   is_a("slashing", "physical") -> true
##   is_a("physical", "physical") -> true
##   is_a("fire",     "physical") -> false
static func is_a(subtype: String, ancestor: String) -> bool:
	var current := subtype
	while current != "":
		if current == ancestor:
			return true
		current = PARENTS.get(current, "")
	return false
