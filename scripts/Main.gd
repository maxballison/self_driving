# Main.gd
extends Node

# Assuming your Level scene’s player is a child of Level.
@onready var player = $Player
@onready var code_editor = $CanvasLayer/CodeEditor
@onready var interpreter = $ScriptInterpreter

@export var run_delay = 0.5

func _ready():
	# Let the interpreter know which player to command.
	interpreter.player = player
