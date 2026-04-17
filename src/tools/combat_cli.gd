## Headless combat runner.
##
## Usage:
##   godot --headless --script src/tools/combat_cli.gd -- [flags]
##
## Flags:
##   --seed <int>        RNG seed (default 0)
##   --scenario <id>     Scenario id (default "basic")
##   --format text|jsonl Output format in auto mode (default text)
##   --max-rounds <int>  Safety cap (default 100)
##   --interactive       Prompt the player to control party members
##
## Prerequisite: run the import step once before using --script tools:
##   godot --headless --import --quit
##
## This tool must remain runnable without a display server. It is the
## fastest way to prototype combat mechanics and regression-test them.
extends SceneTree

const DEFAULT_SEED: int = 0
const DEFAULT_SCENARIO: String = "basic"
const DEFAULT_MAX_ROUNDS: int = 100

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var seed_value: int = int(args.get("seed", DEFAULT_SEED))
	var scenario_id: String = args.get("scenario", DEFAULT_SCENARIO)
	var format_str: String = args.get("format", "text")
	var max_rounds: int = int(args.get("max-rounds", DEFAULT_MAX_ROUNDS))
	var interactive: bool = args.has("interactive")

	var state := ScenarioLoader.load_scenario(scenario_id)
	if state == null:
		quit(1)
		return

	var rng := SeededRng.new(seed_value)
	var engine := CombatEngine.new(state, rng)

	if interactive:
		engine.event_emitted.connect(_print_event)
		engine.start(StringName(scenario_id))
		_run_interactive(engine, max_rounds)
	else:
		var log := CombatLog.new()
		log.bind(engine)
		engine.start(StringName(scenario_id))
		_run_auto(engine, max_rounds)
		var format := CombatLog.Format.JSONL if format_str == "jsonl" else CombatLog.Format.TEXT
		print(log.render(format))

	quit()

## Auto-resolves a fight: every actor attacks the first living enemy on the
## opposing side using the cheapest affordable attack profile.
func _run_auto(engine: CombatEngine, max_rounds: int) -> void:
	while not engine.is_ended() and engine.state().round_number <= max_rounds:
		var actor := engine.current_actor()
		if actor == null:
			break
		var action := _auto_action(engine, actor)
		if action == null:
			break
		engine.submit_action(action)

## Interactive mode — party members choose actions; enemies auto-attack.
func _run_interactive(engine: CombatEngine, max_rounds: int) -> void:
	while not engine.is_ended() and engine.state().round_number <= max_rounds:
		var actor := engine.current_actor()
		if actor == null:
			break
		var action: CombatAction
		if actor.side == Combatant.Side.PARTY:
			action = _prompt_action(engine, actor)
		else:
			action = _auto_action(engine, actor)
		if action == null:
			break
		engine.submit_action(action)

func _auto_action(engine: CombatEngine, actor: Combatant) -> CombatAction:
	var enemy_side: Combatant.Side = Combatant.Side.FOES \
			if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
	var targets := engine.state().living_on_side(enemy_side)
	if targets.is_empty():
		return null
	# If we can afford any attack profile, attack. Otherwise end turn.
	if _has_affordable_attack(actor):
		return CombatAction.new(actor.id, CombatAction.Type.ATTACK, [targets[0].id])
	return CombatAction.new(actor.id, CombatAction.Type.END_TURN)

func _has_affordable_attack(actor: Combatant) -> bool:
	for p in actor.attack_profiles:
		if p.weapon.action_point_cost <= actor.action_points:
			return true
	return false

## Prints events to stdout as they happen (used in interactive mode).
func _print_event(event: CombatEvent) -> void:
	match event.type:
		CombatEvent.Type.COMBAT_STARTED:
			print("=== Combat started  seed:%s  scenario:'%s' ===" % [
					str(event.payload.get("seed", "?")),
					str(event.payload.get("scenario_id", "?"))])
		CombatEvent.Type.ROUND_STARTED:
			print("\n--- Round %d ---" % event.round_number)
		CombatEvent.Type.DAMAGE_DEALT:
			print("  %s hits %s for %d %s damage  [HP %d -> %d]" % [
					str(event.payload.get("source_id", "?")),
					str(event.payload.get("target_id", "?")),
					int(event.payload.get("amount", 0)),
					str(event.payload.get("damage_type", "?")),
					int(event.payload.get("hp_before", 0)),
					int(event.payload.get("hp_after", 0))])
		CombatEvent.Type.ATTACK_MISSED:
			print("  %s -> %s: %s" % [
					str(event.payload.get("source_id", "?")),
					str(event.payload.get("target_id", "?")),
					String(event.payload.get("outcome", "miss")).to_upper()])
		CombatEvent.Type.COMBATANT_FELL:
			print("  *** %s fell! ***" % str(event.payload.get("combatant_id", "?")))
		CombatEvent.Type.COMBAT_ENDED:
			print("\n=== Combat over  winner:%s  reason:%s  rounds:%d ===" % [
					str(event.payload.get("winner", "?")),
					str(event.payload.get("reason", "?")),
					int(event.payload.get("duration_rounds", 0))])

func _prompt_action(engine: CombatEngine, actor: Combatant) -> CombatAction:
	var enemy_side: Combatant.Side = Combatant.Side.FOES \
			if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
	var enemy_targets := engine.state().living_on_side(enemy_side)
	if enemy_targets.is_empty():
		return null
	print("\n> %s  HP %d/%d  AP %d/%d" % [
			actor.display_name, actor.hp, actor.stats.max_hp,
			actor.action_points, actor.stats.max_action_points])
	for i in actor.attack_profiles.size():
		var prof := actor.attack_profiles[i]
		print("  profile [%d] %s (%s)  dmg %d-%d  ap %d" % [
				i + 1, prof.display_name, prof.weapon.weapon_kind,
				prof.weapon.damage_min, prof.weapon.damage_max,
				prof.weapon.action_point_cost])
	for i in enemy_targets.size():
		var t := enemy_targets[i]
		print("  enemy [%d] %s  HP %d/%d" % [i + 1, t.display_name, t.hp, t.stats.max_hp])
	print("  [a]ttack  [d]efend  [e]nd turn")
	var choice := OS.read_string_from_stdin().strip_edges().to_lower()

	if choice == "d":
		return CombatAction.new(actor.id, CombatAction.Type.DEFEND)
	if choice == "e":
		return CombatAction.new(actor.id, CombatAction.Type.END_TURN)

	var profile_idx := 0
	if actor.attack_profiles.size() > 1:
		print("  Profile [1-%d]:" % actor.attack_profiles.size())
		var p_str := OS.read_string_from_stdin().strip_edges()
		profile_idx = clamp(int(p_str) - 1, 0, actor.attack_profiles.size() - 1)
	var profile_id := actor.attack_profiles[profile_idx].profile_id

	var target_idx := 0
	if enemy_targets.size() > 1:
		print("  Target [1-%d]:" % enemy_targets.size())
		var t_str := OS.read_string_from_stdin().strip_edges()
		target_idx = clamp(int(t_str) - 1, 0, enemy_targets.size() - 1)
	return CombatAction.new(
			actor.id, CombatAction.Type.ATTACK,
			[enemy_targets[target_idx].id], &"", profile_id)

func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var value: String = "true"
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				value = argv[i + 1]
				i += 1
			out[key] = value
		i += 1
	return out
