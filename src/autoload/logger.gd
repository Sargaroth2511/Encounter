## Thin logging facade used by outer layers (features, tools).
##
## src/core/ does NOT use this — core code expresses its narrative through
## CombatEvents instead. This logger is for developer-facing diagnostics
## (scene loads, platform info, save errors).
extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

var min_level: Level = Level.INFO

func debug(msg: String) -> void: _emit(Level.DEBUG, msg)
func info(msg: String) -> void:  _emit(Level.INFO, msg)
func warn(msg: String) -> void:  _emit(Level.WARN, msg)
func error(msg: String) -> void: _emit(Level.ERROR, msg)

func _emit(level: Level, msg: String) -> void:
	if level < min_level:
		return
	var tag: String = Level.keys()[level]
	print("[%s] %s" % [tag, msg])
