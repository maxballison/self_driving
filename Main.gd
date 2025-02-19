# Main.gd
extends Node

# Assuming your Level scene’s player is a child of Level.
@onready var level = $Level
@onready var player = $Level/Player
@onready var code_editor = $CanvasLayer/CodeEditor
@onready var interpreter = $ScriptInterpreter

func _ready():
	# Let the interpreter know which player to command.
	interpreter.player = player
