extends Node
class_name TutorialManager

# Tutorial data structure
# Format: {
#   "level_path": {
#     "messages": [message1, message2, ...],
#     "functions": [{ name, description, example, category }, ...]
#   }
# }
var tutorial_data: Dictionary = {}

func _ready() -> void:
	# Load tutorials and functions from file
	load_tutorials_from_file("res://data/tutorial_data.json")

func register_tutorial_for_level(level_path: String, messages: Array, functions: Array = []) -> void:
	tutorial_data[level_path] = {
		"messages": messages,
		"functions": functions
	}

func get_messages_for_level(level_path: String) -> Array:
	if tutorial_data.has(level_path) and tutorial_data[level_path].has("messages"):
		return tutorial_data[level_path]["messages"]
	else:
		# Return a default message if no specific tutorial exists
		return ["No specific tutorial for this level.\n\nUse the [code]drive()[/code] command to navigate."]

func get_functions_for_level(level_path: String) -> Array:
	print("Getting functions for level:", level_path)
	var available_functions = []
	
	# Find this level's functions
	if tutorial_data.has(level_path) and tutorial_data[level_path].has("functions"):
		print("Found functions in tutorial data:", tutorial_data[level_path]["functions"].size())
		available_functions = tutorial_data[level_path]["functions"]
	else:
		print("No functions found for this level in tutorial data")
	
	# For debugging, print the first function if available
	if available_functions.size() > 0:
		print("First function:", available_functions[0].get("name", "unnamed"))
	
	return available_functions

# Helper function to extract level number from path
func _extract_level_number(level_path: String) -> int:
	var regex = RegEx.new()
	regex.compile("level_(\\d+)")
	var result = regex.search(level_path)
	
	if result:
		return int(result.get_string(1))
	return 0

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
			# Process tutorial data
			for level_path in data.keys():
				var level_data = data[level_path]
				if level_data is Array:
					# Old format - just an array of messages
					register_tutorial_for_level(level_path, level_data)
				elif level_data is Dictionary:
					# New format - dictionary with messages and functions
					var messages = level_data.get("messages", [])
					var functions = level_data.get("functions", [])
					register_tutorial_for_level(level_path, messages, functions)
		else:
			push_error("Unexpected data format in tutorial file.")
	else:
		push_error("JSON Parse Error: " + str(error))

func save_tutorials_to_file(file_path: String) -> void:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open tutorial file for writing: " + file_path)
		return
	
	var json_text = JSON.stringify(tutorial_data, "\t")
	file.store_string(json_text)
	file.close()
