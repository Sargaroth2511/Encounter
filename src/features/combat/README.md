# Feature: Combat

Visual + input layer for fights. The actual rules live in `src/core/combat/`.

## Entry point

`combat_controller.gd` owns a `CombatEngine` and subscribes to its
`event_emitted` signal. The scene (TSCN, to be built) reacts to events —
it never reads engine state directly.

## Dependencies

- `src/core/combat/*` — the simulation (read-only consumer).
- `src/autoload/event_bus.gd` — signals fight-finished out to other features.
- `src/shared/ui/*` — HP bars, turn indicators (to be added).

## What NOT to do here

- Do not implement combat rules. Add them to `src/core/rules/`.
- Do not call `CombatEngine` methods that aren't part of its public surface
  (start, submit_action, current_actor, state, is_ended).
- Do not import from other features (`world_map`, `main_menu`). Use EventBus.
