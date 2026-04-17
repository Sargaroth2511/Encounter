## Deterministic RNG wrapper.
##
## All randomness in src/core/ MUST flow through this class. Never call
## randi()/randf() directly inside the combat simulation — it breaks
## reproducibility, replays, and snapshot tests.
class_name SeededRng
extends RefCounted

var _rng: RandomNumberGenerator
var _seed: int

func _init(seed_value: int = 0) -> void:
	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

func seed() -> int:
	return _seed

## Integer in [min_value, max_value] inclusive.
func randi_range(min_value: int, max_value: int) -> int:
	return _rng.randi_range(min_value, max_value)

## Float in [0.0, 1.0).
func randf() -> float:
	return _rng.randf()

## True with the given probability (0.0 .. 1.0).
func chance(probability: float) -> bool:
	return _rng.randf() < probability

## Uniform pick from a non-empty array.
func pick(items: Array) -> Variant:
	assert(not items.is_empty(), "pick() on empty array")
	return items[_rng.randi_range(0, items.size() - 1)]
