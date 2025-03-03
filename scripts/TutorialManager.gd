extends Node
class_name TutorialManager

# Tutorial messages for each level
# Format: { "level_path": [message1, message2, ...] }
var tutorial_messages: Dictionary = {}

func _ready() -> void:
	# Register default tutorials for each level
	#register_default_tutorials()
	load_tutorials_from_file("res://data/tutorial_data.json")

func register_default_tutorials() -> void:
	# Here you can define default messages for each level
	# These can be overridden by loading from a file later
	
	# Level 1 tutorial
	register_tutorial_for_level("res://GeneratedLevels/level_1.tscn", [
		"[b]Welcome to the Coding Adventure![/b]\n\nIn this game, you'll learn to write code to control your character through various levels.",
		"Use the [color=#80CCFF]Code Editor[/color] to write instructions for your character.\n\nFor example, try typing:\n[code]move(\"East\")[/code]\nand then click [color=#80CCFF]Run[/color] to move your character.",
		"The basic commands you can use are:\n[code]move(\"North\")[/code]\n[code]move(\"South\")[/code]\n[code]move(\"East\")[/code]\n[code]move(\"West\")[/code]",
		"Try to reach the [color=#FFCC80]door[/color] to advance to the next level.\n\nGood luck on your coding journey!"
	])
	
	# Level 2 tutorial
	register_tutorial_for_level("res://GeneratedLevels/level_2.tscn", [
		"[b]Level 2: Variables[/b]\n\nNow let's learn about variables. Variables let you store and reuse values.",
		"Try creating a variable to store a direction:\n[code]var direction = \"East\"\nmove(direction)[/code]",
		"You can change the value of a variable:\n[code]var direction = \"East\"\nmove(direction)\ndirection = \"South\"\nmove(direction)[/code]",
		"Use variables to make your code cleaner and more flexible!"
	])
	
	# Level 3 tutorial
	register_tutorial_for_level("res://GeneratedLevels/level_3.tscn", [
		"[b]Level 3: Loops[/b]\n\nLoops let you repeat code multiple times without writing it again and again.",
		"Try using a [color=#80CCFF]for loop[/color] to move multiple times:\n[code]for i in range(3):\n    move(\"East\")[/code]",
		"You can also use a [color=#80CCFF]while loop[/color]:\n[code]var steps = 0\nwhile steps < 3:\n    move(\"East\")\n    steps = steps + 1[/code]",
		"Loops are powerful tools to make your code more efficient!"
	])
	
	# Level 4 tutorial
	register_tutorial_for_level("res://GeneratedLevels/level_4.tscn", [
		"[b]Level 4: Functions[/b]\n\nFunctions let you group code that belongs together.",
		"Define a function like this:\n[code]func move_twice(direction):\n    move(direction)\n    move(direction)[/code]",
		"Then call it like this:\n[code]move_twice(\"East\")[/code]",
		"Functions help you organize your code and reuse logic across your program."
	])

func register_tutorial_for_level(level_path: String, messages: Array) -> void:
	tutorial_messages[level_path] = messages

func get_messages_for_level(level_path: String) -> Array:
	if tutorial_messages.has(level_path):
		return tutorial_messages[level_path]
	else:
		# Return a default message if no specific tutorial exists
		return ["No specific tutorial for this level.\n\nUse [code]move()[/code] commands to navigate."]

func load_tutorials_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("Tutorial file not found: " + file_path)
		return
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Could not open tutorial file: " + file_path)
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error == OK:
		var data = json.get_data()
		if data is Dictionary:
			# Merge with existing tutorials (override duplicates)
			for level in data:
				if data[level] is Array:
					tutorial_messages[level] = data[level]
		else:
			push_error("Unexpected data format in tutorial file.")
	else:
		push_error("JSON Parse Error: " + str(error))

func save_tutorials_to_file(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open tutorial file for writing: " + file_path)
		return
	
	var json_text = JSON.stringify(tutorial_messages, "\t")
	file.store_string(json_text)
	file.close()
