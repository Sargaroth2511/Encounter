## Project-wide signal hub for cross-feature communication.
##
## Features must NOT import each other directly. If feature A needs to tell
## feature B something, it fires a signal here; B listens.
##
## Keep this file free of game rules — it is a pipe, not a brain.
extends Node

signal scene_change_requested(scene_id: StringName, payload: Dictionary)
signal combat_requested(scenario_id: StringName)
signal combat_finished(winner: StringName, summary: Dictionary)
signal save_requested()
signal settings_changed(key: StringName, value: Variant)
