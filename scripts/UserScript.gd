# UserScript.gd
extends Node

var player  # This will be set by the interpreter.

func move(direction):
	if player:
		player.move(direction)
	else:
		push_error("No player assigned!")
