# Tests

Headless-runnable tests for the combat core and supporting code.

## Layout

```
tests/unit/             Isolated class tests (one class under test each).
tests/integration/      Multi-class flows (e.g. a full fight).
tests/fixtures/         Stored scenario inputs + expected JSONL outputs.
```

## Running

```bash
godot --headless --script tests/run_all.gd
```

(The runner is a small script that instantiates each `test_*.gd` — to be
added alongside your first real tests.)

## Writing a new test

1. One file per class under test: `tests/unit/combat/test_<class>.gd`.
2. Test is a `SceneTree` script or a simple `RefCounted` with `run()`.
3. Assert on **emitted events**, not internal state. The event stream is
   the contract.

## Snapshot tests

For a scenario with known inputs, produce a JSONL log via the CLI and store
it as `tests/fixtures/<scenario>.seed<N>.jsonl`. The test re-runs the
scenario and diffs against the fixture. Any drift = intentional change
(update fixture) or regression (fix code).
