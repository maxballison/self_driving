# UserScript.gd
extends Node


signal instruction_step
var player  # This will be set by the interpreter.

func move(direction):
	if player:
		player.move(direction)
	else:
		push_error("No player assigned!")
	wait()

func wait():
	emit_signal("instruction_step")
