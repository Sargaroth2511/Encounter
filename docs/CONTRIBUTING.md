# Contributing

Read this before adding code. It exists so the project stays coherent as it
grows.

## Setup

1. Install **Godot 4.3+** (stable channel).
2. Clone the repo, open `project.godot` in Godot.
3. Confirm you can run the combat CLI:
   ```bash
   godot --headless --script src/tools/combat_cli.gd -- --seed 1 --scenario basic
   ```
   You should see a text combat log in stdout. If not, stop and fix that first.

## Code style

- **GDScript 2.0 (Godot 4).** Static typing everywhere — no untyped `var`.
  - Bad: `var hp = 10`
  - Good: `var hp: int = 10`
- **`class_name` on every script** that defines a class used by another file.
- **`snake_case`** for files, variables, functions. **`PascalCase`** for class
  names. **`SCREAMING_SNAKE`** for constants.
- **Signals** are verbs in past tense: `damage_dealt`, `turn_started`.
- **Prefer composition.** Don't inherit from `Combatant` to make a `Goblin` —
  a `Goblin` is data fed into a `Combatant`.
- **No comments that restate code.** Comments only explain *why* when the
  reason isn't obvious.
- Follow [.editorconfig](../.editorconfig): tabs in `.gd`, LF endings.

## The golden rules (from ARCHITECTURE.md)

Before you commit, your change must satisfy:

- [ ] No file in `src/core/` imports anything from `src/features/`,
      `src/shared/`, or `src/autoload/`.
- [ ] No file in `src/core/` extends `Node`, `Node2D`, `Control`, or uses
      `get_tree()`.
- [ ] No `randi()` / `randf()` / real-time calls inside `src/core/`. Use the
      injected `SeededRng`.
- [ ] No feature imports another feature directly. Cross-feature traffic
      goes via `EventBus` or `GameState`.
- [ ] Every new combat mechanic emits a typed `CombatEvent` — nothing is
      ever "implicit state change."
- [ ] If you added content (enemy, spell, item), it lives in `assets/data/`
      as a resource, not in code.

## How to add X

### A new combat ability (spell, attack, buff)

1. Add a `SpellDef` / `AbilityDef` resource in `assets/data/spells/`.
2. If it needs a new rule primitive (e.g. "lifesteal"), add it to
   `src/core/rules/`.
3. Add a unit test under `tests/unit/combat/` that runs the ability in
   isolation and asserts the emitted event sequence.
4. Add a scenario fixture under `tests/fixtures/` that exercises it end-to-end,
   and snapshot its log output.

### A new enemy

1. Create `assets/data/enemies/<name>.tres` (instance of `EnemyDef`).
2. If its behavior uses only existing mechanics — **you are done.**
   That is the point of data-driven content.
3. If it needs a new mechanic, follow "new combat ability" above first.

### A new feature (screen, mode)

1. Create `src/features/<feature>/` with its own scene, controller, widgets.
2. Add a `src/features/<feature>/README.md` (1 paragraph: purpose, entry
   point, dependencies).
3. Wire entry/exit via `EventBus`, not direct calls from other features.
4. If the feature touches combat, it subscribes to combat events — it does
   **not** reach into `CombatEngine` internals.

### A dev tool

1. Drop it in `src/tools/`.
2. It must be runnable headless (`godot --headless --script ...`).
3. Add a one-liner invocation example to the tool's header comment.

## Testing requirements

- Anything under `src/core/` should have at least one unit test.
- Any balance-sensitive mechanic needs a scenario snapshot test.
- UI changes: at minimum, open the scene and click through the golden path
  manually; note it in the PR.

## Commit / PR hygiene

- One logical change per commit. "Refactor X + fix Y + add Z" = three commits.
- Commit message subject ≤ 70 chars, imperative mood: `add fireball spell`.
- If the change crosses a layer boundary or bends a Layer Rule, mention it
  explicitly in the PR description.
- Breaking changes to the combat event schema require a version bump in
  [COMBAT_LOG.md](COMBAT_LOG.md) and an ADR.

## When rules get in your way

The rules serve the goal (coherent, testable, portable game). If a rule
blocks a legitimate need, don't quietly violate it — write an ADR
(`docs/adr/NNNN-title.md`) that states the problem, the proposed exception,
and the consequences. Then the rule changes, or your case becomes the
documented exception.
