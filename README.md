# Encounter

Turn-based fantasy combat, playable on desktop (Steam) and mobile (iOS/Android).
Built with **Godot 4** and designed around a headless, deterministic combat core.

## Why this matters: the Combat Log

Every fight produces a **structured, human-readable log**. The log is not a
debug afterthought — it is the primary interface during prototyping. You can
play, test, balance, and automate encounters entirely from the command line
before a single sprite exists. When the UI is later added, it subscribes to
the **same event stream** that produces the log, so text and visuals can
never drift apart.

See [docs/COMBAT_LOG.md](docs/COMBAT_LOG.md) for the event schema and format.

## Quick links

- Architecture & layer rules → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- How to add a feature / ability → [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
- Combat log spec → [docs/COMBAT_LOG.md](docs/COMBAT_LOG.md)
- Architecture decisions → [docs/adr/](docs/adr/)

## Layout

```
src/core/        Pure game logic. No scene-tree deps. Headless-runnable.
src/features/    One folder per feature (combat, world_map, main_menu, ...).
src/shared/      Cross-feature UI widgets, input, save service.
src/autoload/    Godot singletons (EventBus, GameState, Log).
src/tools/       Dev tooling — the CLI runner lives here.
assets/          Sprites, audio, fonts, data (.tres / .json).
tests/           Unit + integration tests (headless).
docs/            Architecture, contribution rules, ADRs, log spec.
```

## Running the combat CLI

```bash
# From the project root (requires Godot 4 on PATH):
godot --headless --script src/tools/combat_cli.gd -- --seed 42 --scenario basic
```

Output is a deterministic log you can diff across runs. See
[docs/COMBAT_LOG.md](docs/COMBAT_LOG.md) for flags and format.

## Running tests

```bash
godot --headless --script tests/run_all.gd
```

## Targets

| Platform | Status | Notes |
|---|---|---|
| Windows (Steam) | planned | Primary desktop target |
| macOS / Linux (Steam) | planned | Same export pipeline |
| Android | planned | Touch UI, portrait-first |
| iOS | planned | Same |
