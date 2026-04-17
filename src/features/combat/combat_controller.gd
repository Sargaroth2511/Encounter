## Glue between the pure CombatEngine and the visual scene.
##
## Pattern:
##   - Controller OWNS the engine and the log (for in-game developer view).
##   - Controller subscribes to `event_emitted` and translates events into
##     scene-level method calls (play animation, update HP bar).
##   - Scene NEVER inspects engine internals. It only reacts to events.
##
## This file is a template — fill it in when you build the combat scene.
class_name CombatController
extends Node

@export var dump_log_on_end: bool = true

var _engine: CombatEngine
var _log: CombatLog

func start_fight(state: CombatState, rng: SeededRng, scenario_id: StringName) -> void:
	_engine = CombatEngine.new(state, rng)
	_log = CombatLog.new()
	_log.bind(_engine)
	_engine.event_emitted.connect(_on_event)
	_engine.start(scenario_id)

func submit_player_action(action: CombatAction) -> void:
	_engine.submit_action(action)

func _on_event(event: CombatEvent) -> void:
	match event.type:
		CombatEvent.Type.DAMAGE_DEALT:
			# TODO: play hit animation on event.payload.target_id
			pass
		CombatEvent.Type.COMBATANT_FELL:
			# TODO: play fall animation
			pass
		CombatEvent.Type.COMBAT_ENDED:
			if dump_log_on_end:
				Log.info("\n" + _log.render(CombatLog.Format.TEXT))
			EventBus.combat_finished.emit(
				StringName(event.payload.get("winner", "")),
				event.payload,
			)
