## Primary stat block for a combatant. Pure data.
##
## Attack damage is no longer a stat — it comes from the wielded weapon
## (see WeaponDef / AttackProfile). Defense is split into dodge / parry
## (avoidance) and armor (mitigation). Speed is replaced by an
## action-point budget refilled every round.
class_name Stats
extends Resource

@export var max_hp: int = 10
@export var max_mp: int = 0
@export var max_action_points: int = 3
@export var hit_chance: int = 70    # percent, base
@export var dodge: int = 5          # percent
@export var parry: int = 0          # percent, added to weapon.parry_bonus
@export var armor: int = 0          # percent mitigation on hit, clamped 0..95

func duplicate_stats() -> Stats:
	var s := Stats.new()
	s.max_hp = max_hp
	s.max_mp = max_mp
	s.max_action_points = max_action_points
	s.hit_chance = hit_chance
	s.dodge = dodge
	s.parry = parry
	s.armor = armor
	return s

static func from_dict(data: Dictionary) -> Stats:
	var s := Stats.new()
	s.max_hp            = int(data.get("max_hp",            s.max_hp))
	s.max_mp            = int(data.get("max_mp",            s.max_mp))
	s.max_action_points = int(data.get("max_action_points", s.max_action_points))
	s.hit_chance        = int(data.get("hit_chance",        s.hit_chance))
	s.dodge             = int(data.get("dodge",             s.dodge))
	s.parry             = int(data.get("parry",             s.parry))
	s.armor             = int(data.get("armor",             s.armor))
	return s

func with_overrides(overrides: Dictionary) -> Stats:
	var s := duplicate_stats()
	if overrides.has("max_hp"):            s.max_hp            = int(overrides["max_hp"])
	if overrides.has("max_mp"):            s.max_mp            = int(overrides["max_mp"])
	if overrides.has("max_action_points"): s.max_action_points = int(overrides["max_action_points"])
	if overrides.has("hit_chance"):        s.hit_chance        = int(overrides["hit_chance"])
	if overrides.has("dodge"):             s.dodge             = int(overrides["dodge"])
	if overrides.has("parry"):             s.parry             = int(overrides["parry"])
	if overrides.has("armor"):             s.armor             = int(overrides["armor"])
	return s
