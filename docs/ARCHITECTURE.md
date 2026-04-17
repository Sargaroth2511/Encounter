# Architecture

Encounter is a turn-based RPG built on a **headless deterministic core** plus
**thin presentation layers**. Every fight is a function of its inputs — same
seed + same actions = same events. This property is the bedrock of
prototyping, testing, balancing, and replays.

## Layering

```
┌─────────────────────────────────────────────────────────────┐
│  src/features/*         Scenes, UI, controllers (per feature)│
│  src/shared/*           Reusable widgets, input, save        │
│  src/autoload/*         EventBus, GameState, Log (singletons)│
│  src/tools/*            CLI runners, replayer, balancing     │
├─────────────────────────────────────────────────────────────┤
│                          src/core/*                          │
│         Pure logic. No Node. No scene tree. No UI.           │
└─────────────────────────────────────────────────────────────┘
```

**Dependency direction is strictly downward.** Outer layers may import from
`src/core/`. `src/core/` must import **nothing** from outer layers.

## The Layer Rules (non-negotiable)

1. **`src/core/` is engine-agnostic.**
   - No `extends Node` / `Node2D` / `Control` — use `RefCounted` or `Resource`.
   - No `get_tree()`, no `await` on frame timing, no `_process()`.
   - No `preload` of anything outside `src/core/`.
   - This is what lets the CLI run the combat headless.
2. **`src/features/` never imports another feature directly.**
   - Cross-feature communication goes through `EventBus` or `GameState`.
   - This keeps features independently removable.
3. **`src/autoload/` holds only services, not game rules.**
   - `GameState` stores data, it does not compute combat outcomes.
   - Combat rules belong in `src/core/rules/`.
4. **`assets/data/`, not code, defines content.**
   - New enemies, spells, and items are `.tres` / `.json` files. Code changes
     should not be required to add a new sword.
5. **Every gameplay event is a typed `CombatEvent`** (or equivalent).
   - The UI never asks "what happened?" — it receives events.

If you want to bend one of these rules, write an ADR in [adr/](adr/) first.

## Combat flow

```
     Inputs                Core                     Subscribers
  ┌──────────┐       ┌───────────────┐       ┌──────────────────┐
  │ Scenario │──────▶│ CombatEngine  │──────▶│ CombatLog (text) │
  │ Seed     │       │  + CombatState│──────▶│ Scene UI widgets │
  │ Actions  │──────▶│  + SeededRng  │──────▶│ Analytics, tests │
  └──────────┘       └───────────────┘       └──────────────────┘
```

- `CombatEngine` (in `src/core/combat/`) owns the simulation.
- It consumes `CombatAction`s and emits `CombatEvent`s.
- `CombatLog` is one subscriber that formats events into text.
- In-game UI is another subscriber, bound in `src/features/combat/`.
- The CLI runner (`src/tools/combat_cli.gd`) wires scenario + log + stdin/out.

## Determinism

- All randomness flows through `SeededRng` (`src/core/rng/`).
- **No** `randi()`, `randf()`, or `Time.get_unix_time_from_system()` inside
  `src/core/`. Use the injected RNG and explicit turn counters.
- Given the same inputs, the event sequence must be byte-identical across
  runs and platforms. This is what makes bug reports reproducible (attach
  the log + seed).

## Platform abstraction

- Touch vs mouse/keyboard differences live in `src/shared/input/`.
- Platform detection (Steam vs mobile) goes through an autoload service;
  features consume the service, not `OS.get_name()` directly.
- UI scenes should layout-respond to viewport aspect; avoid hardcoded pixel
  positions. Portrait is the default canvas.

## Data-driven content

Content files live in `assets/data/` as Godot `Resource` (`.tres`) files or
JSON:

```text
assets/data/enemies/goblin.json       # EnemyDef: stats + attack profiles
assets/data/weapons/shortsword.json   # WeaponDef: damage, AP cost, parry
assets/data/spells/fireball.tres      # SpellDef (not yet implemented)
assets/data/scenarios/tutorial.json   # Scripted encounter for CLI/tests
```

The core defines the schemas; designers edit JSON (or `.tres` in Godot's
inspector). No code change needed to add a new enemy or weapon — see the
Combat model section below.

## Combat model (schema 2.0)

The simulation is built around three pillars — see
[ADR 0002](adr/0002-weapon-ap-hit-pipeline.md) for the full rationale.

**Weapons and attack profiles.** A combatant does not have a scalar
`attack` stat. Instead they carry a list of `AttackProfile`s ("main_hand",
"off_hand", "tail", "bite"), each pointing at a `WeaponDef` that supplies
damage range, AP cost, `hit_bonus`, `parry_bonus`, `weapon_kind`, and a
`parryable` flag. Natural attacks are just weapons tagged
`weapon_kind = "natural"`. Loaded by `WeaponLoader` from
`assets/data/weapons/`.

**Hit pipeline.** `src/core/rules/hit_rules.gd` runs every attack through
hit → dodge → parry → armor:

1. Hit roll: `clamp(attacker.hit_chance + weapon.hit_bonus, 5, 95)`.
2. Dodge roll: `clamp(defender.dodge, 0, 95)`.
3. Parry roll: `clamp(defender.parry + best_parry_bonus, 0, 95)`, gated by
   `weapon.parryable` and the defender's `parry_allowed_kinds` if set.
4. Damage roll from the weapon, then armor applies as a percentage
   mitigation (`clamp(defender.armor, 0, 95)`), minimum 1 if raw > 0.

Each branch emits distinct events — `attack_missed` (with an `outcome` of
miss / dodged / parried) or `damage_dealt` (carrying both `raw_damage` and
`armor_pct`).

**Action points.** There is no `speed`. Each combatant has
`max_action_points`, refilled at the start of every round. Initiative
order (once per round) is max AP desc, id asc. The engine rotates actors
through the queue, spending AP per action; an actor with AP left goes to
the back of the queue and gets another turn slot. A 4-AP fighter with a
2-AP weapon acts twice per round; a 6-AP rogue with a 1-AP dagger acts six
times. Round ends when everyone's AP drops below `MIN_TURN_AP`.

## Balancing

Every combatant has a `score` computed by `src/core/rules/scoring.gd` —
weighted sum of stats + expected weapon throughput. Tune the weights
against batch win-rate, not intuition:

```bash
# 100 fights, default seeds, text summary
godot --headless --script src/tools/combat_batch.gd -- \
    --scenario balance_duel --runs 100
```

A well-calibrated score produces ~50% win-rate at score parity. If win-rate
and score diverge, the weights are wrong, not the fight.

## Damage types

Every hit carries a `damage_type` string. Types are organised in a two-level
hierarchy defined in `src/core/rules/damage_type.gd`:

```
physical  ←  slashing  piercing  bludgeoning
magical   ←  fire  ice  lightning  arcane
```

`DamageType.is_a(type, "physical")` returns `true` for any physical subtype.
This will drive resistances and weaknesses once those systems exist.

**Where the type comes from:** the `damage_type` field on the `WeaponDef`
used for the attack. Each `AttackProfile` points at a weapon, so a
combatant with a sword (`slashing`) and a dagger (`piercing`) emits the
correct type per swing. `DAMAGE_DEALT` events carry `damage_type`,
`weapon_id`, and `profile_id` so the log and UI can attribute the hit.

## CLI runner (`src/tools/combat_cli.gd`)

Two modes, selected by flag:

| Mode | Flag | Behaviour |
|---|---|---|
| **Auto** *(default)* | *(no flag)* | Every actor attacks the first living enemy on the opposing side. Outputs a full structured log at the end. Supports `--format text\|jsonl`. |
| **Interactive** | `--interactive` | Events print live. On a party member's turn the player is prompted to choose `[a]ttack` or `[d]efend`; if multiple enemies are alive, a target is also chosen. Enemies still auto-attack. |

Both modes respect `--seed`, `--scenario`, and `--max-rounds`.

## Testing

- Pure core classes are trivially unit-testable (instantiate, call, assert).
- Combat scenarios are snapshot-tested: run a seeded scenario, compare the
  resulting log against a stored fixture.
- UI is smoke-tested with Godot's built-in scene runner.

## What lives where — quick reference

| I want to... | Put it in |
|---|---|
| Add a new spell effect | `src/core/rules/` + a `.tres` in `assets/data/spells/` |
| Add a new enemy type | `assets/data/enemies/*.tres` — no code unless it needs new mechanics |
| Add a new combat UI widget | `src/features/combat/widgets/` |
| Add a new screen (inventory, shop) | new folder under `src/features/` |
| Add a dev-only automation | `src/tools/` |
| Add cross-feature state | `src/autoload/game_state.gd` |
| Add cross-feature signals | `src/autoload/event_bus.gd` |
| Add a platform check | `src/autoload/` platform service, not inline |
