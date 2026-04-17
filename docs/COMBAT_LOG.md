# Combat Log Specification

The combat log is the canonical record of what happened in a fight. It is
produced by subscribing to `CombatEngine`'s event stream — the **same stream**
the UI renders. UI and log can never disagree.

**Schema version:** `2.0.0` (bumped for the weapon / AP / hit-pipeline
redesign — see [ADR 0002](adr/0002-weapon-ap-hit-pipeline.md)).
Pre-2.0 logs are not replayable against the current core.

## Goals

1. **Human-readable at a glance.** A designer skims it and understands the fight.
2. **Machine-parseable.** A test diffs two runs and fails loud on mismatch.
3. **Deterministic.** Same seed + actions → byte-identical log.
4. **Complete.** Every state change is an event. No "off the record" effects.

## Event types (v2.0.0)

| Event | Fields | When |
| --- | --- | --- |
| `combat_started` | `seed`, `participants[]`, `scenario_id`, `schema_version` | Once, at fight start |
| `round_started` | `round` | Start of each round |
| `turn_started` | `round`, `actor_id` | Before an actor acts (each AP-spend is its own turn slot) |
| `action_declared` | `actor_id`, `action_type`, `target_ids[]`, `ability_id?`, `profile_id?`, `ap_cost` | Actor commits to an action |
| `attack_missed` | `source_id`, `target_id`, `weapon_id`, `profile_id`, `outcome` (`miss`/`dodged`/`parried`), `hit_chance`, `dodge_chance`, `parry_chance`, `parry_weapon_id?` | Attack did not land |
| `damage_dealt` | `source_id`, `target_id`, `weapon_id`, `profile_id`, `amount`, `raw_damage`, `armor_pct`, `damage_type`, `hp_before`, `hp_after` | Any HP reduction |
| `healed` | `source_id`, `target_id`, `amount`, `hp_before`, `hp_after` | Any HP increase |
| `status_applied` | `target_id`, `status`, `duration`, `source_id` | Buff/debuff applied |
| `status_expired` | `target_id`, `status` | Buff/debuff fell off |
| `resource_changed` | `actor_id`, `resource`, `before`, `after` | Mana, stamina, etc. |
| `action_points_changed` | `actor_id`, `before`, `after`, `delta`, `reason` | AP spent or refilled |
| `combatant_fell` | `combatant_id` | HP reached 0 |
| `turn_ended` | `round`, `actor_id` | After an actor's turn resolves |
| `round_ended` | `round` | End of each round |
| `combat_ended` | `winner`, `reason`, `duration_rounds`, `survivors[]` | Fight resolved |

New events must be added to `src/core/combat/combat_event.gd` and this table
together, with a schema-version bump if the change is breaking.

## Text format

Each line:

```text
[R{round}:T{turn} tick={tick}] {SUBJECT} {VERB} [{OBJECT}]{ : detail}
```

- `round` = 1-based round number.
- `turn` = 1-based turn-slot within the round. A single combatant can
  occupy multiple turn slots in one round if they have AP to spare.
- `tick` = global monotonic event counter since `combat_started`.

### Example

```text
[R0:T0 tick=1] COMBAT start  seed=42 scenario=basic  schema=2.0.0
[R1:T0 tick=2] ROUND 1 begin
[R1:T1 tick=3] Aria     turn start
[R1:T1 tick=4] Aria     declares ATTACK [main_hand] -> Goblin#1  ap=2
[R1:T1 tick=5] Aria     hits Goblin#1 : 4 slashing  armor -5% (raw 5)  (hp 15 -> 11)
[R1:T1 tick=6] Aria     AP 4 -> 2  (attack)
[R1:T1 tick=7] Aria     turn end
[R1:T2 tick=8] Goblin#1 turn start
[R1:T2 tick=9] Goblin#1 declares ATTACK [bite] -> Aria  ap=1
[R1:T2 tick=10] Goblin#1 -> Aria : MISS  (hit 65%)
...
[R4:T3 tick=100] COMBAT end   winner=party  reason=all_foes_down  rounds=4
```

- Amounts and state transitions always show `before -> after`; never
  "Aria takes damage".
- On a hit the log prints `armor -N%` when armor mitigated a fraction,
  alongside the raw roll, so designers can see what got absorbed.

## JSON format (machine-readable)

Used by tests and the replayer. Same events, one JSON object per line (JSONL):

```json
{"tick":5,"round":1,"turn":1,"type":"damage_dealt","source_id":"aria","target_id":"goblin_1","weapon_id":"shortsword","profile_id":"main_hand","amount":4,"raw_damage":5,"armor_pct":5,"damage_type":"slashing","hp_before":15,"hp_after":11}
```

The CLI runner emits text by default; pass `--format jsonl` for JSON.

## CLI usage

```bash
# Text, seeded, scripted scenario
godot --headless --script src/tools/combat_cli.gd -- \
    --seed 42 --scenario basic

# JSONL for diffing against a fixture
godot --headless --script src/tools/combat_cli.gd -- \
    --seed 42 --scenario basic --format jsonl > run.jsonl

# Interactive: choose attacks, defends, end-turns on stdin
godot --headless --script src/tools/combat_cli.gd -- --interactive
```

Flags:

| Flag | Meaning |
| --- | --- |
| `--seed <int>` | RNG seed (default: 0) |
| `--scenario <id>` | Load `assets/data/scenarios/<id>.json` |
| `--format text\|jsonl` | Output format (default: text) |
| `--interactive` | Prompt for actions on stdin |
| `--max-rounds <int>` | Safety cap (default: 100) |

## Batch / balancing runner

For balance work, use `src/tools/combat_batch.gd`. It runs a scenario many
times with varying seeds and prints roster scores, win-rate, round
distribution, and survivor HP%.

```bash
# 100 fights on balance_duel, compare party vs foes score
godot --headless --script src/tools/combat_batch.gd -- \
    --scenario balance_duel --runs 100

# JSONL summary for logging to a file / diffing across changes
godot --headless --script src/tools/combat_batch.gd -- \
    --scenario balance_duel --runs 500 --format jsonl
```

Score is computed by `Scoring` (`src/core/rules/scoring.gd`). Its weights
are first-guess; tune them against win-rate data, not intuition. A
well-calibrated score should produce ~50% win-rate at parity (same score on
both sides).

## Replay

A saved JSONL log + its seed can be replayed to reproduce the fight
exactly. This is how bug reports should be filed — the log is the repro.

```bash
godot --headless --script src/tools/combat_replayer.gd -- --input run.jsonl
```

## Rules for changing the schema

- Adding a new event type: **minor** bump (`2.0.0` → `2.1.0`). Document in
  this file + add the event class.
- Renaming a field, removing an event, changing semantics: **major** bump
  (`2.0.0` → `3.0.0`). Requires an ADR and a fixture-regeneration pass.
- Never emit events with new fields without adding them here first.
