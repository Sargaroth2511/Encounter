# 0001 — Deterministic combat core

- **Status:** accepted
- **Date:** 2026-04-17

## Context

Encounter is a turn-based RPG that must ship on Steam and mobile. During
development, we need fast iteration on combat balance without waiting for
UI, art, or animation. During testing, we need the same fight to produce
the same outcome every time. After release, we need player bug reports we
can actually reproduce.

A combat system that is entangled with the scene tree, calls `randi()`
inline, and couples visual state to game state can satisfy none of these.

## Decision

The combat simulation lives in `src/core/combat/` as pure `RefCounted` /
`Resource` classes. It has **no** dependency on the Godot scene tree, no
`Node` ancestors, no `_process()` timing, and no access to real-time or
untracked RNG.

- All randomness flows through a `SeededRng` injected at construction.
- All state changes are expressed as typed `CombatEvent` instances emitted
  through a signal.
- The `CombatLog` and the in-game UI are **both** subscribers to that event
  stream — neither is privileged.
- A headless CLI runner (`src/tools/combat_cli.gd`) can execute any
  scenario end-to-end without Godot's display server.

## Consequences

**Easier:**
- Prototyping new mechanics without touching UI.
- Unit-testing combat in isolation.
- Reproducing bugs from a user-supplied log + seed.
- Balancing via scripted batch runs.
- Porting to other engines later if we ever needed to.

**Harder / committed to:**
- Contributors must respect the layer boundary. See CONTRIBUTING.md.
- We cannot use Godot niceties like `await get_tree().create_timer()` inside
  core — turn pacing is expressed in event sequence, not wall-clock time.
- Every mechanic must be expressible as events. "Hidden" state changes are
  forbidden by construction.
- The event schema is now a public contract; breaking changes cost an ADR.
