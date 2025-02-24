# ScriptInterpreter.gd
extends Node

# This reference is set from Main.gd.
var player: Node = null

# Public method to be called from the CodeEditor.
# Now compiles the given GDScript code at runtime.
func execute_script(script_text: String) -> void:
	# If the user's code doesn't specify an extends, automatically extend our base script.
	if not script_text.begins_with("extends"):
		script_text = "extends \"res://scripts/UserScript.gd\"\n" + script_text

	var script = GDScript.new()
	script.source_code = script_text

	# Try compiling the script.
	var error = script.reload()
	if error != OK:
		push_error("Script compilation error: " + str(error))
		return

	# Instance the script.
	var script_instance = script.new()
	add_child(script_instance)

	# Set the player reference so the helper functions work.
	script_instance.connect("instruction_step", Callable(self, "_on_instruction_step"))
	script_instance.player = player

	# Look for a run() method to execute.
	if script_instance.has_method("run"):
		script_instance.run()
	else:
		push_error("The provided script does not have a 'run()' method.")
		
func _on_instruction_step():
	print('Hello')
	await get_tree().create_timer(0.5).timeout
