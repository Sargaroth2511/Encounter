# 0002 — Weapon / AP / hit-pipeline redesign

- **Status:** accepted
- **Date:** 2026-04-17
- **Supersedes (in part):** 0001 (schema 1.0.0 → 2.0.0, not the determinism
  principle, which stands)

## Context

The original combat model (schema 1.0.0) had `attack` and `defense` as
scalar stats on `Stats`, `speed` for turn order, and a single `damage_type`
string on `Combatant`. This was enough for one-hero-vs-one-goblin smoke
tests but blocks every next feature:

- No weapons as first-class entities: equipment cannot affect damage,
  AP cost, or parry without growing `Stats` indefinitely.
- No multiple attack sources per combatant (main hand + off hand;
  bite + claws + tail).
- "Defense" is a single number with ambiguous semantics — it flattens
  avoidance and mitigation into one knob, which makes balancing impossible.
- `speed` gives one action per round. We want characters with more action
  budget to act more often within a round — light daggers fast, heavy axes
  slow — which a scalar initiative cannot express.
- No way to measure whether an encounter is balanced short of playing it.

## Decision

Break the schema to 2.0.0 and introduce:

1. **WeaponDef + AttackProfile.** Weapons are loaded from
   `assets/data/weapons/<id>.json` and carry damage, AP cost,
   `hit_bonus`, `parry_bonus`, `weapon_kind`, and a `parryable` flag.
   Each combatant exposes a list of `AttackProfile`s — each profile names
   a body part or slot ("main_hand", "tail") and references a weapon.
   Natural attacks are weapons tagged `weapon_kind = "natural"`.

2. **Split defense into dodge / parry / armor.** `Stats` now carries
   `hit_chance`, `dodge`, `parry`, `armor`. Resolution pipeline:
   hit roll → dodge roll → parry roll → damage roll → armor mitigation.
   Parry is gated by `weapon.parryable` and by the defender's weapons
   (some kinds can't parry arrows; some can). Pipeline lives in
   `src/core/rules/hit_rules.gd`.

3. **Replace `speed` with action points.** Every combatant has
   `max_action_points`, refilled at the start of each round. Actions
   cost AP (weapon's `action_point_cost` for attacks). Turn order within
   a round is determined by initiative (max AP desc, id asc); the engine
   rotates actors through the queue, re-queuing any actor with AP left
   until the queue is empty. A 4-AP fighter with a 2-AP weapon acts twice
   a round; a 6-AP fighter with a 1-AP dagger acts six times.

4. **Scoring.** `src/core/rules/scoring.gd` computes a single power number
   per combatant from stats and weapons. Used by `combat_batch` to report
   whether a fight is balanced. Weights are first-guess; they tune against
   win-rate data from batch runs, not intuition.

5. **Batch runner.** `src/tools/combat_batch.gd` runs N fights of a
   scenario (default 100) with incrementing seeds and prints roster,
   score totals, win-rate, round distribution, and survivor HP%. This is
   the primary balancing interface.

6. **New events.** `ATTACK_MISSED` (covering miss / dodge / parry with an
   `outcome` field) and `ACTION_POINTS_CHANGED` join the event stream.
   `DAMAGE_DEALT` now also carries `raw_damage`, `armor_pct`, `weapon_id`,
   and `profile_id`. Schema bumped to 2.0.0.

## Consequences

**Easier:**
- Adding a new weapon is data-only (`assets/data/weapons/*.json`).
- Balancing: `combat_batch` gives empirical win-rate + survivor HP% per
  scenario in seconds. Score delta + win-rate delta → weight corrections.
- Multi-limb creatures, ranged attacks, and future ability systems all fit
  without further schema breaks — they are new weapons or new action
  types, not new fields on `Stats`.

**Harder / committed to:**
- Pre-2.0 logs cannot be replayed against this core. The old format is
  historical.
- The auto-picker chooses the cheapest profile by default — AI
  sophistication (target prioritisation, profile selection, AP budgeting)
  is a future concern; today's runner is intentionally naive.
- Scoring is a heuristic, not ground truth. It must be recalibrated
  whenever we add a stat, a weapon axis, or a mechanic that changes
  expected value. Batch results are the arbiter.
