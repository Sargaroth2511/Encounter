## Balance-testing batch runner.
##
## Runs a scenario many times with varying seeds and reports aggregate
## results — the primary tool for tuning stats, weapon numbers, and
## Scoring weights. Lives alongside combat_cli.gd; uses the same core
## engine, just with no log output per fight.
##
## Usage:
##   godot --headless --script src/tools/combat_batch.gd -- \
##       --scenario balance_duel --runs 100
##
## Flags:
##   --scenario <id>      Scenario id (default "basic")
##   --runs <n>           Number of fights (default 100)
##   --seed-start <int>   First seed; each run uses seed_start + i (default 1)
##   --max-rounds <int>   Safety cap per fight (default 100)
##   --verbose            Print one line per fight (seed, winner, rounds)
##   --format text|jsonl  Summary format (default text)
##
## Exit codes: 0 always, even if "foes" win — this is a measurement tool,
## not a test. Tests live under tests/.
extends SceneTree

const DEFAULT_SCENARIO: String = "basic"
const DEFAULT_RUNS: int = 100
const DEFAULT_SEED_START: int = 1
const DEFAULT_MAX_ROUNDS: int = 100

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var scenario_id: String = args.get("scenario", DEFAULT_SCENARIO)
	var runs: int = int(args.get("runs", DEFAULT_RUNS))
	var seed_start: int = int(args.get("seed-start", DEFAULT_SEED_START))
	var max_rounds: int = int(args.get("max-rounds", DEFAULT_MAX_ROUNDS))
	var verbose: bool = args.has("verbose")
	var format_str: String = args.get("format", "text")

	var results: Array[Dictionary] = []
	var roster_summary: Array = []
	for i in runs:
		var state := ScenarioLoader.load_scenario(scenario_id)
		if state == null:
			quit(1)
			return
		if roster_summary.is_empty():
			roster_summary = _describe_roster(state)
		var rng := SeededRng.new(seed_start + i)
		var engine := CombatEngine.new(state, rng)
		var res := _run_one(engine, state, seed_start + i, max_rounds)
		results.append(res)
		if verbose:
			print("run %d  seed=%d  winner=%s  rounds=%d" % [
					i + 1, seed_start + i, res["winner"], res["rounds"]])

	var summary := _summarize(scenario_id, runs, seed_start, roster_summary, results)
	if format_str == "jsonl":
		print(JSON.stringify(summary))
	else:
		print(_format_summary(summary))
	quit()

func _run_one(engine: CombatEngine, state: CombatState, seed_value: int, max_rounds: int) -> Dictionary:
	engine.start(StringName("batch"))
	var safety: int = 0
	while not engine.is_ended() and engine.state().round_number <= max_rounds:
		var actor := engine.current_actor()
		if actor == null:
			break
		var enemy_side: Combatant.Side = Combatant.Side.FOES \
				if actor.side == Combatant.Side.PARTY else Combatant.Side.PARTY
		var targets := state.living_on_side(enemy_side)
		if targets.is_empty():
			break
		var action: CombatAction
		if _has_affordable_attack(actor):
			action = CombatAction.new(actor.id, CombatAction.Type.ATTACK, [targets[0].id])
		else:
			action = CombatAction.new(actor.id, CombatAction.Type.END_TURN)
		engine.submit_action(action)
		safety += 1
		if safety > 50000:
			break

	var winner := "timeout"
	var reason := "max_rounds"
	# Inspect last event for winner; fallback to state inspection.
	var party_alive := state.living_on_side(Combatant.Side.PARTY).size()
	var foes_alive  := state.living_on_side(Combatant.Side.FOES).size()
	if engine.is_ended():
		if party_alive > 0 and foes_alive == 0:
			winner = "party"; reason = "all_foes_down"
		elif foes_alive > 0 and party_alive == 0:
			winner = "foes"; reason = "all_party_down"
		else:
			winner = "draw"; reason = "stalemate"
	return {
		"seed": seed_value,
		"winner": winner,
		"reason": reason,
		"rounds": state.round_number,
		"party_hp_pct": _side_hp_pct(state, Combatant.Side.PARTY),
		"foes_hp_pct":  _side_hp_pct(state, Combatant.Side.FOES),
		"party_fictive_hp_pct": _side_fictive_hp_pct(state, Combatant.Side.PARTY),
		"foes_fictive_hp_pct":  _side_fictive_hp_pct(state, Combatant.Side.FOES),
		"party_survivors": party_alive,
		"foes_survivors":  foes_alive,
	}

func _has_affordable_attack(actor: Combatant) -> bool:
	for p in actor.attack_profiles:
		if p.weapon.action_point_cost <= actor.action_points:
			return true
	return false

func _side_hp_pct(state: CombatState, side: int) -> float:
	var hp: int = 0
	var max_hp: int = 0
	for c in state.combatants:
		if c.side == side:
			hp += max(0, c.hp)
			max_hp += c.stats.max_hp
	return 0.0 if max_hp == 0 else float(hp) / float(max_hp)

## Fictive HP fraction — includes overkill as negative HP.
## Range: [−∞, 1.0]. Dead but barely beaten → 0. Obliterated → large negative.
func _side_fictive_hp_pct(state: CombatState, side: int) -> float:
	var fictive_hp: float = 0.0
	var max_hp: int = 0
	for c in state.combatants:
		if c.side == side:
			fictive_hp += float(c.hp - c.overkill)
			max_hp += c.stats.max_hp
	return 0.0 if max_hp == 0 else fictive_hp / float(max_hp)

func _describe_roster(state: CombatState) -> Array:
	var out: Array = []
	var by_side: Dictionary = {
		Combatant.Side.PARTY: [],
		Combatant.Side.FOES: [],
	}
	for c in state.combatants:
		var row := {
			"id": String(c.id),
			"name": c.display_name,
			"side": Combatant.Side.keys()[c.side].to_lower(),
			"hp": c.stats.max_hp,
			"ap": c.stats.max_action_points,
			"hit": c.stats.hit_chance,
			"dodge": c.stats.dodge,
			"parry": c.stats.parry,
			"armor": c.stats.armor,
			"score": Scoring.compute(c),
			"profiles": _profiles_summary(c),
		}
		out.append(row)
		by_side[c.side].append(row)
	return out

func _profiles_summary(c: Combatant) -> Array:
	var out: Array = []
	for p in c.attack_profiles:
		out.append({
			"id": String(p.profile_id),
			"weapon": String(p.weapon.weapon_id),
			"dmg_min": p.weapon.damage_min,
			"dmg_max": p.weapon.damage_max,
			"ap": p.weapon.action_point_cost,
			"hit_bonus": p.weapon.hit_bonus,
			"parry_bonus": p.weapon.parry_bonus,
		})
	return out

func _summarize(
		scenario_id: String, runs: int, seed_start: int,
		roster: Array, results: Array[Dictionary]) -> Dictionary:
	var wins_party: int = 0
	var wins_foes: int = 0
	var draws: int = 0
	var timeouts: int = 0
	var round_sum: int = 0
	var round_min: int = 0x7FFFFFFF
	var round_max: int = 0
	var party_hp_sum: float = 0.0
	var foes_hp_sum: float = 0.0
	var party_fictive_sum: float = 0.0
	var foes_fictive_sum: float = 0.0
	for r in results:
		match r["winner"]:
			"party":   wins_party += 1
			"foes":    wins_foes += 1
			"draw":    draws += 1
			"timeout": timeouts += 1
		round_sum += r["rounds"]
		round_min = min(round_min, r["rounds"])
		round_max = max(round_max, r["rounds"])
		party_hp_sum += r["party_hp_pct"]
		foes_hp_sum  += r["foes_hp_pct"]
		party_fictive_sum += r["party_fictive_hp_pct"]
		foes_fictive_sum  += r["foes_fictive_hp_pct"]
	if results.is_empty():
		round_min = 0
	var n: float = float(max(1, results.size()))
	var party_score: int = 0
	var foes_score: int = 0
	for row in roster:
		if row["side"] == "party":
			party_score += int(row["score"])
		else:
			foes_score += int(row["score"])
	return {
		"scenario": scenario_id,
		"runs": runs,
		"seed_start": seed_start,
		"roster": roster,
		"totals": {
			"party_score": party_score,
			"foes_score":  foes_score,
			"score_ratio": 0.0 if foes_score == 0 else float(party_score) / float(foes_score),
		},
		"results": {
			"party_wins":  wins_party,
			"foes_wins":   wins_foes,
			"draws":       draws,
			"timeouts":    timeouts,
			"party_win_rate": float(wins_party) / n,
			"foes_win_rate":  float(wins_foes)  / n,
			"avg_rounds": float(round_sum) / n,
			"min_rounds": round_min,
			"max_rounds": round_max,
			"avg_party_hp_remaining": party_hp_sum / n,
			"avg_foes_hp_remaining":  foes_hp_sum  / n,
			"avg_party_fictive_hp_remaining": party_fictive_sum / n,
			"avg_foes_fictive_hp_remaining":  foes_fictive_sum  / n,
		},
	}

func _format_summary(s: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("=== Batch results: %s  runs=%d  seed-start=%d ===" % [
			s["scenario"], int(s["runs"]), int(s["seed_start"])])
	lines.append("-- Roster --")
	for row in s["roster"]:
		lines.append("  [%s] %-16s score=%-4d  hp=%-3d ap=%-2d hit=%-2d dodge=%-2d parry=%-2d armor=%-2d" % [
				row["side"], row["name"], int(row["score"]),
				int(row["hp"]), int(row["ap"]), int(row["hit"]),
				int(row["dodge"]), int(row["parry"]), int(row["armor"])])
		for p in row["profiles"]:
			lines.append("      - %s via %s  dmg=%d-%d ap=%d  +hit=%d +parry=%d" % [
					p["id"], p["weapon"], int(p["dmg_min"]), int(p["dmg_max"]),
					int(p["ap"]), int(p["hit_bonus"]), int(p["parry_bonus"])])
	lines.append("-- Totals --")
	lines.append("  party score: %d   foes score: %d   ratio: %.2f" % [
			int(s["totals"]["party_score"]),
			int(s["totals"]["foes_score"]),
			float(s["totals"]["score_ratio"])])
	var r: Dictionary = s["results"]
	lines.append("-- Results --")
	lines.append("  party win-rate: %.1f%%  (%d/%d)" % [
			float(r["party_win_rate"]) * 100.0, int(r["party_wins"]), int(s["runs"])])
	lines.append("  foes  win-rate: %.1f%%  (%d/%d)" % [
			float(r["foes_win_rate"]) * 100.0, int(r["foes_wins"]), int(s["runs"])])
	lines.append("  draws: %d   timeouts: %d" % [int(r["draws"]), int(r["timeouts"])])
	lines.append("  rounds: avg=%.2f  min=%d  max=%d" % [
			float(r["avg_rounds"]), int(r["min_rounds"]), int(r["max_rounds"])])
	lines.append("  avg HP remaining: party=%.1f%%  foes=%.1f%%" % [
			float(r["avg_party_hp_remaining"]) * 100.0,
			float(r["avg_foes_hp_remaining"])  * 100.0])
	lines.append("  avg fictive HP:   party=%.1f%%  foes=%.1f%%" % [
			float(r["avg_party_fictive_hp_remaining"]) * 100.0,
			float(r["avg_foes_fictive_hp_remaining"])  * 100.0])
	return "\n".join(lines)

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
