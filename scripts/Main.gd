# Main.gd
extends Node

# Core components
@onready var player = $Player
@onready var tutorial_window = $TutorialWindow
@onready var interpreter = $ScriptInterpreter
@onready var level_manager = $LevelManager

@export var run_delay = 0.5

func _ready():
	# Setup interpreter
	interpreter.player = player
	
	# Initialize tutorial system
	if level_manager:
		if not level_manager.is_connected("level_switched", Callable(self, "_on_level_switched")):
			level_manager.connect("level_switched", Callable(self, "_on_level_switched"))
		
		# Manually trigger first tutorial
		_on_level_switched()
	
	# Debug info
	print("Main scene initialized")
	print("Tutorial window position: ", tutorial_window.position)
	print("Tutorial window size: ", tutorial_window.size)

func _on_level_switched():
	# Show tutorial when level changes
	if tutorial_window:
		tutorial_window.visible = true
		
		# If TutorialManager not available, set default messages
		if not has_node("/root/TutorialManager"):
			var current_level = level_manager.current_level_instance.scene_file_path if level_manager.current_level_instance else "unknown"
			var default_messages = [
				"[b]Welcome to Level " + current_level.get_basename().get_file() + "![/b]",
				"Use the [color=#80CCFF]Code Editor[/color] to control your character.\n\nTry commands like:\n[code]move(\"North\")[/code]\n[code]move(\"East\")[/code]",
				"Click the [color=#80FF80]Run[/color] button to execute your code."
			]
			tutorial_window.set_tutorial_messages(default_messages)
