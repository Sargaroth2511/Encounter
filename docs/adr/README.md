# Architecture Decision Records

Short, dated write-ups of decisions that shape the project. One decision per
file. Format is loosely based on Michael Nygard's ADR template.

## When to write one

- You are about to violate or change a Layer Rule (ARCHITECTURE.md).
- You are making a technology choice that will be annoying to reverse
  (engine, networking library, save format, platform SDK).
- You are introducing a cross-cutting concept (e.g. event schema, RNG model)
  that the whole codebase will depend on.

## Format

```
# NNNN — Title (verb phrase)

- **Status:** proposed | accepted | superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
What forces are at play? What problem are we solving?

## Decision
What we chose to do, stated plainly.

## Consequences
What becomes easier. What becomes harder. What we are committing to.
```

## Numbering

Zero-padded, monotonically increasing. Never reuse numbers. Superseded ADRs
stay in the tree — they are history, not garbage.

## Index

- [0001 — Deterministic combat core](0001-deterministic-combat-core.md)
- [0002 — Weapon / AP / hit-pipeline redesign](0002-weapon-ap-hit-pipeline.md)
