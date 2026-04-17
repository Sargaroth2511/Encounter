## Typed events emitted by CombatEngine.
##
## Every gameplay state change MUST be expressed as a CombatEvent. This is
## the contract between simulation and any subscriber (log, UI, tests,
## analytics). See docs/COMBAT_LOG.md for the schema.
##
## Schema version: 2.0.0 — breaking rewrite for the weapon / AP / hit
## pipeline (ADR 0002). Old 1.x logs cannot be replayed against this core.
class_name CombatEvent
extends RefCounted

const SCHEMA_VERSION: String = "2.0.0"

enum Type {
	COMBAT_STARTED,
	ROUND_STARTED,
	TURN_STARTED,
	ACTION_DECLARED,
	ATTACK_MISSED,        ## miss / dodge / parry — reason in payload.outcome
	DAMAGE_DEALT,
	HEALED,
	STATUS_APPLIED,
	STATUS_EXPIRED,
	RESOURCE_CHANGED,
	ACTION_POINTS_CHANGED,
	COMBATANT_FELL,
	TURN_ENDED,
	ROUND_ENDED,
	COMBAT_ENDED,
}

var tick: int = 0
var round_number: int = 0
var turn_number: int = 0
var type: Type
var payload: Dictionary = {}

func _init(type_: Type, payload_: Dictionary = {}) -> void:
	type = type_
	payload = payload_

func type_name() -> String:
	return Type.keys()[type].to_lower()

func to_dict() -> Dictionary:
	return {
		"tick": tick,
		"round": round_number,
		"turn": turn_number,
		"type": type_name(),
	}.merged(payload)
