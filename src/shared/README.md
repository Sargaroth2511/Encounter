# Shared

Cross-feature, non-core code. UI widgets reused across scenes, input
abstraction (touch vs mouse/keyboard), the save service, platform probes.

Rules:
- Nothing in here depends on a specific feature.
- Nothing in here reaches into `src/core/`'s innards — it may import core
  types but must not mutate core state directly.
- If a widget is only used by one feature, it lives in that feature's
  folder instead.
