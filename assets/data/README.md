# Data

Content definitions as Godot `Resource` (`.tres`) files or JSON.

```
assets/data/enemies/      EnemyDef resources
assets/data/spells/       SpellDef resources
assets/data/items/        ItemDef resources
assets/data/scenarios/    Scripted encounters for CLI + tests
```

Adding a new enemy, spell, or item should be a **data-only** change in this
folder. If it needs a new underlying mechanic, add that to `src/core/rules/`
first, then reference it from the data file.
