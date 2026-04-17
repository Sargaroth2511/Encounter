## Text and JSONL formatter for CombatEvents.
##
## Subscribes to a CombatEngine via its `event_emitted` signal, appends each
## event, and can render the whole run as text or JSONL. See
## docs/COMBAT_LOG.md for the format spec.
class_name CombatLog
extends RefCounted

enum Format { TEXT, JSONL }

var _events: Array[CombatEvent] = []
var _state_ref: CombatState

func bind(engine: CombatEngine) -> void:
	_state_ref = engine.state()
	engine.event_emitted.connect(_on_event)

func events() -> Array[CombatEvent]:
	return _events

func render(format: Format = Format.TEXT) -> String:
	var lines: PackedStringArray = []
	for e in _events:
		lines.append(_format_line(e, format))
	return "\n".join(lines) + "\n"

func _on_event(event: CombatEvent) -> void:
	_events.append(event)

func _format_line(e: CombatEvent, format: Format) -> String:
	match format:
		Format.JSONL:
			return JSON.stringify(e.to_dict())
		_:
			return _format_text(e)

func _format_text(e: CombatEvent) -> String:
	var prefix := "[R%d:T%d tick=%d]" % [e.round_number, e.turn_number, e.tick]
	var p := e.payload
	match e.type:
		CombatEvent.Type.COMBAT_STARTED:
			return "%s COMBAT start  seed=%s scenario=%s  schema=%s" % [
					prefix, p.get("seed"), p.get("scenario_id"), p.get("schema_version", "?")]
		CombatEvent.Type.ROUND_STARTED:
			return "%s ROUND %d begin" % [prefix, e.round_number]
		CombatEvent.Type.ROUND_ENDED:
			return "%s ROUND %d end" % [prefix, e.round_number]
		CombatEvent.Type.TURN_STARTED:
			return "%s %s turn start" % [prefix, _name(p.get("actor_id"))]
		CombatEvent.Type.TURN_ENDED:
			return "%s %s turn end" % [prefix, _name(p.get("actor_id"))]
		CombatEvent.Type.ACTION_DECLARED:
			var extra := ""
			if p.get("profile_id", "") != "":
				extra = " [" + str(p.get("profile_id")) + "]"
			return "%s %s declares %s%s -> %s  ap=%d" % [
					prefix, _name(p.get("actor_id")), p.get("action_type", "?").to_upper(),
					extra, _names(p.get("target_ids", [])), int(p.get("ap_cost", 0))]
		CombatEvent.Type.ATTACK_MISSED:
			return "%s %s -> %s : %s  (%s)" % [
					prefix, _name(p.get("source_id")), _name(p.get("target_id")),
					String(p.get("outcome", "miss")).to_upper(),
					_miss_detail(p)]
		CombatEvent.Type.DAMAGE_DEALT:
			var armor_note := ""
			if int(p.get("armor_pct", 0)) > 0:
				armor_note = "  armor -%d%% (raw %d)" % [int(p.get("armor_pct", 0)), int(p.get("raw_damage", 0))]
			return "%s %s hits %s : %d %s%s  (hp %d -> %d)" % [
					prefix, _name(p.get("source_id")), _name(p.get("target_id")),
					p.get("amount", 0), p.get("damage_type", "physical"),
					armor_note,
					p.get("hp_before", 0), p.get("hp_after", 0),
			]
		CombatEvent.Type.HEALED:
			return "%s %s heals %s : %d  (hp %d -> %d)" % [
					prefix, _name(p.get("source_id")), _name(p.get("target_id")),
					p.get("amount", 0), p.get("hp_before", 0), p.get("hp_after", 0),
			]
		CombatEvent.Type.ACTION_POINTS_CHANGED:
			return "%s %s AP %d -> %d  (%s)" % [
					prefix, _name(p.get("actor_id")),
					int(p.get("before", 0)), int(p.get("after", 0)),
					str(p.get("reason", ""))]
		CombatEvent.Type.COMBATANT_FELL:
			return "%s %s falls" % [prefix, _name(p.get("combatant_id"))]
		CombatEvent.Type.COMBAT_ENDED:
			return "%s COMBAT end   winner=%s  reason=%s  rounds=%d" % [
					prefix, p.get("winner", "?"), p.get("reason", "?"), p.get("duration_rounds", 0),
			]
		_:
			return "%s %s %s" % [prefix, e.type_name(), JSON.stringify(p)]

func _miss_detail(p: Dictionary) -> String:
	match str(p.get("outcome", "")):
		"miss":
			return "hit %s%%" % str(p.get("hit_chance", 0))
		"dodged":
			return "dodge %s%%" % str(p.get("dodge_chance", 0))
		"parried":
			return "parry %s%%" % str(p.get("parry_chance", 0))
		_:
			return ""

func _name(id: Variant) -> String:
	if id == null or _state_ref == null:
		return str(id)
	var c := _state_ref.find(id)
	return c.display_name if c != null else str(id)

func _names(ids: Array) -> String:
	var parts: PackedStringArray = []
	for id in ids:
		parts.append(_name(id))
	return ",".join(parts)
