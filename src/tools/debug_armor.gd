extends SceneTree

const DEFAULT_SCENARIO: String = "basic"
const DEFAULT_RUNS: int = 20

func _initialize() -> void:
    var scenario_id := DEFAULT_SCENARIO
    var runs := DEFAULT_RUNS
    
    for i in runs:
        var state := ScenarioLoader.load_scenario(scenario_id)
        var rng := SeededRng.new(1 + i)
        var engine := CombatEngine.new(state, rng)
        
        engine.event_emitted.connect(func(event: CombatEvent):
            if event.type == CombatEvent.Type.DAMAGE_DEALT:
                var p = event.payload
                print("Damage Event: amount=%d, raw=%d, armor_pct=%.2f" % [p.amount, p.raw_damage, p.armor_pct])
        )
        
        engine.start(StringName("debug"))
        var safety := 0
        while not engine.is_ended() and state.round_number <= 100:
            var actor := engine.current_actor()
            if actor == null: break
            var side := Combatant.Side.FOES if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
            var targets := state.living_on_side(side)
            if targets.is_empty(): break
            
            var action: CombatAction
            var best_p: AttackProfile = null
            for p in actor.attack_profiles:
                if p.weapon.action_point_cost <= actor.action_points:
                    best_p = p
                    break
            
            if best_p:
                action = CombatAction.new(actor.id, CombatAction.Type.ATTACK, [targets[0].id])
            else:
                action = CombatAction.new(actor.id, CombatAction.Type.END_TURN)
            
            engine.submit_action(action)
            safety += 1
            if safety > 1000: break
    
    quit()
