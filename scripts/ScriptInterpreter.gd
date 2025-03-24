extends Node
class_name ScriptInterpreter

@export var player: Node

# Store the lines of code in this array
var code_lines: Array[String] = []
var current_line: int = 0

# Stack of dictionaries for block-based scoping (like Python)
var environment_stack: Array[Dictionary] = []

# Store functions (name -> {start_line, end_line, params})
var functions: Dictionary = {}

# Whether we are currently interpreting
var is_running: bool = false

var code_editor = null

func _ready() -> void:
	# Find the code editor for line highlighting
	code_editor = get_node_or_null("/root/Main/CodeEditorImproved")

# Called by the CodeEditor script to run user code asynchronously
func execute_script(script_text: String) -> void:
	if is_running:
		push_error("Interpreter is already busy executing code.")
		return
	is_running = true

	# Clear old data and set up environment
	environment_stack.clear()
	push_scope()
	functions.clear()

	code_lines.clear()
	for line in script_text.split("\n"):
		code_lines.append(line)

	# First pass: identify and register all function declarations
	_register_functions()
	
	current_line = 0

	await _run_interpreter(0)
	is_running = false
	
# First pass to identify all functions in the code
func _register_functions() -> void:
	var line_idx = 0
	while line_idx < code_lines.size():
		var line_full: String = code_lines[line_idx]
		var line: String = line_full.strip_edges()
		
		if line.begins_with("func ") and line.ends_with(":"):
			var func_name = _extract_function_name(line)
			var params = _extract_function_params(line)
			var indent_level = _count_indent(line_full) + 1
			var start_line = line_idx + 1
			var end_line = _find_block_end(start_line, indent_level)
			
			functions[func_name] = {
				"start_line": start_line,
				"end_line": end_line,
				"params": params
			}
			
			line_idx = end_line
		else:
			line_idx += 1

# Main interpreter logic: processes lines, handles control structures, and yields when needed
func _run_interpreter(indent_level: int) -> void:
	while current_line < code_lines.size() and is_running:
		var line_full: String = code_lines[current_line]
		var line: String = line_full.strip_edges()  # remove leading/trailing whitespace
		var line_indent: int = _count_indent(line_full)

		# If this line's indent is less than the current block's indent,
		# we've reached the end of this block, so return
		if line_indent < indent_level:
			return

		# Highlight the current line in the code editor
		if code_editor != null and code_editor.has_method("highlight_executing_line"):
			code_editor.highlight_executing_line(current_line)

		current_line += 1

		# Skip empty or comment lines
		if line == "" or line.begins_with("#"):
			continue
			
		# Skip function declarations in main execution, they were already registered
		if line.begins_with("func ") and line.ends_with(":"):
			current_line = _find_block_end(current_line, line_indent + 1)
			continue

		# Interpret the line, passing the indent level for control structures
		var result: String = await _interpret_line(line, indent_level)

		if result == "MOVE":
			# Yield for run_delay seconds for move statements
			var t = get_tree().create_timer(owner.run_delay)
			await t.timeout
		elif result == "ERROR":
			push_error("Error in line: %s" % line)
			return
		elif result == "RETURN":
			# Function is returning, so exit current block
			return
			
		if not is_running:
			return

# ----------------------------------------------------------------------
# SCOPING HELPERS
# ----------------------------------------------------------------------
func push_scope() -> void:
	environment_stack.append({})

func pop_scope() -> void:
	if environment_stack.size() > 0:
		environment_stack.pop_back()
	else:
		push_warning("Scope stack is empty; cannot pop.")

func set_var(var_name: String, value: Variant) -> void:
	if environment_stack.size() == 0:
		push_error("No scope available to store variable '%s'." % var_name)
		return
	environment_stack[environment_stack.size() - 1][var_name] = value

func get_var(var_name: String) -> Variant:
	for i in range(environment_stack.size() - 1, -1, -1):
		if environment_stack[i].has(var_name):
			return environment_stack[i][var_name]
	push_warning("Variable '%s' not found in any scope." % var_name)
	return null

# ----------------------------------------------------------------------
# STATEMENT PARSING
# ----------------------------------------------------------------------
# Returns a string from _interpret_line:
# "MOVE" => indicates we did a move statement (requires yield)
# "NONE" => normal or control statement handled
# "ERROR" => if there's an error
# "RETURN" => if we're returning from a function

func _interpret_line(line: String, indent_level: int) -> String:
	if line.begins_with("for ") and line.ends_with(":"):
		return await _handle_for_loop(line, indent_level)
	elif line.begins_with("if ") and line.ends_with(":"):
		return await _handle_if_statement(line, indent_level)
	elif line.begins_with("while ") and line.ends_with(":"):
		return await _handle_while_loop(line, indent_level)
	elif line.begins_with("var "):
		var result_ok = _interpret_var_declaration(line)
		return "NONE" if result_ok else "ERROR"
	elif line.begins_with("drive("):
		var ok = _interpret_drive_statement(line)
		if ok:
			return "MOVE"
		else:
			return "ERROR"
	elif line.begins_with("turn_left("):
		var ok = _interpret_turn_left_statement(line)
		if ok:
			return "MOVE"  # Yield for turn animation
		else:
			return "ERROR"
	elif line.begins_with("turn_right("):
		var ok = _interpret_turn_right_statement(line)
		if ok:
			return "MOVE"  # Yield for turn animation
		else:
			return "ERROR"
	# Add new function interpretations
	elif line.begins_with("pick_up("):
		var ok = _interpret_pick_up_statement(line)
		if ok:
			return "MOVE"  # Yield for animation
		else:
			return "ERROR"
	elif line.begins_with("drop_off("):  # Changed from deliver to drop_off
		var ok = _interpret_drop_off_statement(line)
		if ok:
			return "MOVE"  # Yield for animation
		else:
			return "ERROR"
	# Support older "deliver()" calls for backward compatibility
	elif line.begins_with("deliver("):
		var ok = _interpret_drop_off_statement(line.replace("deliver(", "drop_off("))
		if ok:
			return "MOVE"
		else:
			return "ERROR"
	elif "=" in line and not line.begins_with("if ") and not line.begins_with("while "):
		# Assignment statement (without var)
		var result_ok = _interpret_assignment(line)
		return "NONE" if result_ok else "ERROR"
	elif line.begins_with("return"):
		return "RETURN"
	elif "(" in line and ")" in line:
		# Possible function call
		var result_ok = await _interpret_function_call(line)
		return "NONE" if result_ok else "ERROR"
	else:
		push_warning("Unrecognized statement: %s" % line)
		return "NONE"

# New function to interpret drop_off() statement
func _interpret_drop_off_statement(line: String) -> bool:
	# drop_off() takes no parameters
	var inside = _extract_between(line, "drop_off(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		push_error("drop_off() doesn't take any parameters.")
		return false
		
	if player:
		return player.drop_off()  # Call the new drop_off function
	else:
		push_error("No player assigned to interpreter.")
		return false

func _handle_for_loop(line: String, indent_level: int) -> String:
	# e.g., "for i in range(3):"
	# We'll process the block lines range_count times, each in its own scope

	var stripped = line.strip_edges()
	var after_for = stripped.substr(4, stripped.length() - 5).strip_edges()  # remove "for " and ":"
	
	# Handle "for i in range(x)" format
	if after_for.contains(" in range("):
		var pieces = after_for.split(" in range(")
		if pieces.size() != 2:
			push_error("Invalid for syntax: %s" % line)
			return "ERROR"
			
		var var_name = pieces[0].strip_edges()
		var range_str = pieces[1].strip_edges().replace(")", "")
		
		# Support range with arguments like range(1, 5) or range(0, 10, 2)
		var range_args = range_str.split(",")
		var start = 0
		var end = 0
		var step = 1
		
		if range_args.size() == 1:
			# range(n) - from 0 to n-1
			if not range_args[0].strip_edges().is_valid_int():
				push_error("Range argument must be an integer: %s" % range_args[0])
				return "ERROR"
			end = int(range_args[0].strip_edges())
		elif range_args.size() == 2:
			# range(start, end) - from start to end-1
			if not range_args[0].strip_edges().is_valid_int() or not range_args[1].strip_edges().is_valid_int():
				push_error("Range arguments must be integers: %s" % range_str)
				return "ERROR"
			start = int(range_args[0].strip_edges())
			end = int(range_args[1].strip_edges())
		elif range_args.size() == 3:
			# range(start, end, step)
			if not range_args[0].strip_edges().is_valid_int() or not range_args[1].strip_edges().is_valid_int() or not range_args[2].strip_edges().is_valid_int():
				push_error("Range arguments must be integers: %s" % range_str)
				return "ERROR"
			start = int(range_args[0].strip_edges())
			end = int(range_args[1].strip_edges())
			step = int(range_args[2].strip_edges())
			if step == 0:
				push_error("Range step cannot be zero")
				return "ERROR"
		else:
			push_error("Invalid range syntax: %s" % range_str)
			return "ERROR"

		var block_start = current_line
		var block_end = _find_block_end(block_start, indent_level + 1)

		var i = start
		while (step > 0 and i < end) or (step < 0 and i > end):
			push_scope()
			set_var(var_name, i)  # Set loop variable
			current_line = block_start
			await _run_interpreter(indent_level + 1)
			pop_scope()
			i += step

		current_line = block_end
		return "NONE"
	else:
		push_error("Unsupported for loop syntax: %s" % line)
		return "ERROR"

func _handle_if_statement(line: String, indent_level: int) -> String:
	# e.g., "if x > 0:"
	# If condition is true, process the block in a new scope; otherwise, skip it

	var stripped = line.strip_edges()
	var after_if = stripped.substr(3, stripped.length() - 4).strip_edges()  # remove "if " and ":"
	var cond_str = after_if

	var block_start = current_line
	var block_end = _find_block_end(block_start, indent_level + 1)

	if _eval_condition(cond_str):
		push_scope()
		current_line = block_start
		await _run_interpreter(indent_level + 1)
		pop_scope()
	else:
		# Check for an else block
		var else_line = block_end
		if else_line < code_lines.size():
			var else_line_text = code_lines[else_line].strip_edges()
			if else_line_text == "else:":
				current_line = else_line + 1
				push_scope()
				await _run_interpreter(indent_level + 1)
				pop_scope()
				return "NONE"
	
	current_line = block_end
	return "NONE"

func _handle_while_loop(line: String, indent_level: int) -> String:
	# e.g., "while x > 0:"
	# Process the block in a new scope while the condition is true, up to an iteration limit

	var stripped = line.strip_edges()
	var after_while = stripped.substr(6, stripped.length() - 7).strip_edges()  # remove "while " and ":"
	var cond_str = after_while

	var block_start = current_line
	var block_end = _find_block_end(block_start, indent_level + 1)

	var iteration_limit = 100
	var iteration_count = 0

	while iteration_count < iteration_limit and _eval_condition(cond_str):
		push_scope()
		current_line = block_start
		await _run_interpreter(indent_level + 1)
		pop_scope()
		iteration_count += 1

	if iteration_count >= iteration_limit:
		push_warning("While loop iteration limit reached.")
	current_line = block_end
	return "NONE"

func _interpret_pick_up_statement(line: String) -> bool:
	# pick_up() takes no parameters
	var inside = _extract_between(line, "pick_up(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		push_error("pick_up() doesn't take any parameters.")
		return false
		
	if player:
		return player.pick_up()
	else:
		push_error("No player assigned to interpreter.")
		return false


func _interpret_var_declaration(line: String) -> bool:
	# e.g., "var dir = \"East\""
	var stripped = line.strip_edges()
	var after_var = stripped.substr(4, stripped.length() - 4)
	var pieces = after_var.split("=", true, 1)  # Split only on first =
	if pieces.size() != 2:
		push_error("Invalid var syntax: %s" % line)
		return false
	var var_name = pieces[0].strip_edges()
	var var_value_raw = pieces[1].strip_edges()
	var parsed_value = _parse_value(var_value_raw)
	set_var(var_name, parsed_value)
	return true

func _interpret_assignment(line: String) -> bool:
	# e.g., "x = 5"
	var stripped = line.strip_edges()
	var pieces = stripped.split("=", true, 1)  # Split only on first =
	if pieces.size() != 2:
		push_error("Invalid assignment syntax: %s" % line)
		return false
	var var_name = pieces[0].strip_edges()
	var var_value_raw = pieces[1].strip_edges()
	var parsed_value = _parse_value(var_value_raw)
	
	# Check if variable exists first
	if get_var(var_name) == null:
		push_warning("Creating new variable in assignment: %s" % var_name)
	
	set_var(var_name, parsed_value)
	return true

func _interpret_drive_statement(line: String) -> bool:
	# drive() takes no parameters
	var inside = _extract_between(line, "drive(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		push_error("drive() doesn't take any parameters.")
		return false
		
	if player:
		player.drive()
	else:
		push_error("No player assigned to interpreter.")
		return false
	return true

func _interpret_turn_left_statement(line: String) -> bool:
	# turn_left() takes no parameters
	var inside = _extract_between(line, "turn_left(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		push_error("turn_left() doesn't take any parameters.")
		return false
		
	if player:
		player.turn_left()
	else:
		push_error("No player assigned to interpreter.")
		return false
	return true

func _interpret_turn_right_statement(line: String) -> bool:
	# turn_right() takes no parameters
	var inside = _extract_between(line, "turn_right(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		push_error("turn_right() doesn't take any parameters.")
		return false
		
	if player:
		player.turn_right()
	else:
		push_error("No player assigned to interpreter.")
		return false
	return true

func _interpret_function_call(line: String) -> bool:
	# e.g., "my_function(arg1, arg2)"
	var func_name_end = line.find("(")
	if func_name_end <= 0:
		push_error("Invalid function call syntax: %s" % line)
		return false
		
	var func_name = line.substr(0, func_name_end).strip_edges()
	var args_str = _extract_between(line, "(", ")")
	
	if not functions.has(func_name):
		push_error("Function not found: %s" % func_name)
		return false
		
	var func_info = functions[func_name]
	var param_names = func_info.params
	var arg_values = []
	
	# Parse arguments
	if args_str.strip_edges().length() > 0:
		var arg_strs = args_str.split(",")
		for arg in arg_strs:
			arg_values.append(_parse_value(arg.strip_edges()))
	
	if arg_values.size() != param_names.size():
		push_error("Wrong number of arguments for function %s: expected %d, got %d" % [func_name, param_names.size(), arg_values.size()])
		return false
	
	# Save current execution position
	var saved_line = current_line
	
	# Set up function scope with parameters
	push_scope()
	for i in range(param_names.size()):
		set_var(param_names[i], arg_values[i])
	
	# Execute function body
	current_line = func_info.start_line
	await _run_interpreter(_count_indent(code_lines[func_info.start_line - 1]) + 1)
	
	# Clean up and return to caller
	pop_scope()
	current_line = saved_line
	
	return true

# ----------------------------------------------------------------------
# EXPRESSION / CONDITION PARSING
# ----------------------------------------------------------------------
func _eval_condition(cond_str: String) -> bool:
	if " == " in cond_str:
		var parts = cond_str.split(" == ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left == right
	elif " != " in cond_str:
		var parts = cond_str.split(" != ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left != right
	elif " > " in cond_str:
		var parts = cond_str.split(" > ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left > right
	elif " < " in cond_str:
		var parts = cond_str.split(" < ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left < right
	elif " >= " in cond_str:
		var parts = cond_str.split(" >= ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left >= right
	elif " <= " in cond_str:
		var parts = cond_str.split(" <= ")
		if parts.size() == 2:
			var left = _parse_value(parts[0].strip_edges())
			var right = _parse_value(parts[1].strip_edges())
			return left <= right
	
	# If no operators found, check if the value itself is truthy
	var val = _parse_value(cond_str)
	if val == null:
		return false
	if val is int and val == 0:
		return false
	if val is float and abs(val) < 0.000001:
		return false
	if val is String and val == "":
		return false
	return true

func _parse_value(value_raw: String) -> Variant:
	var trimmed = value_raw.strip_edges()
	# String literals
	if ((trimmed.begins_with("\"") and trimmed.ends_with("\"")) or 
		(trimmed.begins_with("'") and trimmed.ends_with("'"))):
		return trimmed.substr(1, trimmed.length() - 2)
	# Numeric literals
	if trimmed.is_valid_int():
		return int(trimmed)
	if trimmed.is_valid_float():
		return float(trimmed)
	# Boolean literals
	if trimmed == "true":
		return true
	if trimmed == "false":
		return false
	# Basic math operations
	if " + " in trimmed:
		var parts = trimmed.split(" + ")
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			return left + right
	if " - " in trimmed:
		var parts = trimmed.split(" - ")
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			return left - right
	if " * " in trimmed:
		var parts = trimmed.split(" * ")
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			return left * right
	if " / " in trimmed:
		var parts = trimmed.split(" / ")
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			if right == 0:
				push_error("Division by zero")
				return 0
			return left / right
	# Variables
	return get_var(trimmed)

# ----------------------------------------------------------------------
# UTILITY FUNCTIONS
# ----------------------------------------------------------------------
func _find_block_end(start_line: int, indent_level: int) -> int:
	var line_idx = start_line
	while line_idx < code_lines.size():
		var line_full = code_lines[line_idx]
		if line_full.strip_edges() != "":  # Skip empty lines
			var line_indent = _count_indent(line_full)
			if line_indent < indent_level:
				break
		line_idx += 1
	return line_idx

func _count_indent(line: String) -> int:
	var count = 0
	for i in range(line.length()):
		if line[i] == ' ':
			count += 1
		elif line[i] == '\t':
			count += 4  # Count tabs as 4 spaces
		else:
			break
	return count

func _extract_between(text: String, start_token: String, end_token: String) -> String:
	var start_idx = text.find(start_token)
	if start_idx < 0:
		return ""
	start_idx += start_token.length()
	var end_idx = text.find(end_token, start_idx)
	if end_idx < 0:
		return ""
	return text.substr(start_idx, end_idx - start_idx)

func _extract_function_name(func_line: String) -> String:
	var after_func = func_line.substr(5, func_line.length() - 6)  # remove "func " and ":"
	var paren_idx = after_func.find("(")
	if paren_idx < 0:
		return after_func.strip_edges()
	return after_func.substr(0, paren_idx).strip_edges()

func _extract_function_params(func_line: String) -> Array:
	var params = []
	var params_str = _extract_between(func_line, "(", ")")
	if params_str.strip_edges().length() > 0:
		var param_parts = params_str.split(",")
		for part in param_parts:
			params.append(part.strip_edges())
	return params


func _on_player_door_entered(_next_level_path: String, _next_level_spawn: Vector2i) -> void:
	is_running = false
	
func _on_passenger_hit(_passenger) -> void:
	# Stop code execution when a passenger is hit
	print("ScriptInterpreter: Stopping execution due to passenger hit")
	is_running = false
