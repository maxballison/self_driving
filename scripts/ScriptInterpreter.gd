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

signal code_error_detected(line_number: int, error_message: String)


var last_error_line: int = -1
var last_error_message: String = ""


const STANDARD_INDENT_STEP = 4

@export var step_delay: float = 0.1 

func _ready() -> void:
	# Find the code editor for line highlighting
	code_editor = get_node_or_null("/root/Main/CodeEditorImproved")

# Called by the CodeEditor script to run user code asynchronously

func report_error(line: int, message: String) -> void:
	last_error_line = line
	last_error_message = message
	
	# Emit a signal instead of calling the editor directly
	emit_signal("code_error_detected", line, message)
	
	# Always log to console too
	push_error("Error on line %d: %s" % [line, message])
	
	# Stop execution
	is_running = false

func execute_script(script_text: String) -> void:
	if is_running:
		report_error(current_line-1,"Interpreter is already busy executing code.")
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
	
	
	
func reset_state() -> void:
	current_line = 0
	is_running = false
	environment_stack.clear()
	push_scope()  # Initialize with a fresh scope
	
	# Clear any highlighted line in the editor
	if code_editor != null and code_editor.has_method("highlight_executing_line"):
		code_editor.highlight_executing_line(-1)  # -1 means clear highlighting


	
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
func _run_interpreter(indent_level: int) -> Variant: # Return value might be useful later
	while current_line < code_lines.size() and is_running:
		var line_full: String = code_lines[current_line]
		var line_strip: String = line_full.strip_edges()
		var line_indent: int = _count_indent(line_full)
		var line_number_to_interpret = current_line # Store line number before potential skips

		# --- Indentation Handling ---
		if line_strip == "":
			current_line += 1
			continue
		if line_indent < indent_level:
			return "BLOCK_ENDED"
		if line_indent > indent_level:
			report_error(current_line-1,"Skipping line %d due to unexpected indentation level %d (expected %d)." % [current_line, line_indent, indent_level])
			current_line += 1
			continue

		# --- Line Belongs to Current Block (line_indent == indent_level) ---
		var line_content_to_interpret = line_strip
		current_line += 1 # Increment BEFORE interpreting the current line

		# --- Highlighting, Comments, Func Defs ---
		if code_editor != null and code_editor.has_method("highlight_executing_line"):
			code_editor.highlight_executing_line(line_number_to_interpret)
		if line_content_to_interpret.begins_with("#"):
			continue
		if line_content_to_interpret.begins_with("func ") and line_content_to_interpret.ends_with(":"):
			current_line = _find_block_end(current_line, line_indent + STANDARD_INDENT_STEP)
			continue

		# --- Interpret the actual line ---
		# Store result in a variable to check status
		var interpret_result = await _interpret_line(line_content_to_interpret, indent_level)

		# --- Handle results ---
		match interpret_result:
			"STOPPED":
				is_running = false
				return "STOPPED"
			"ERROR":
				report_error(current_line-1,"Error encountered interpreting line %d: %s" % [line_number_to_interpret, line_content_to_interpret])
				is_running = false
				return "ERROR"
			"RETURN":
				return "RETURN"
			# Other results ("NONE", "MOVE") just continue

		# --- Check if stopped externally during await ---
		if not is_running:
			return "STOPPED"

		# ---> ADD BASELINE DELAY HERE <---
		if step_delay > 0.0:
			 # Check is_running again in case the delay itself is interrupted
			if not is_running: return "STOPPED"
			 # Wait for the specified delay
			await get_tree().create_timer(step_delay).timeout
			 # Check one more time after the timer finishes
			if not is_running: return "STOPPED"

	# --- Loop Exit Reasons ---
	if current_line >= code_lines.size(): return "END_OF_FILE"
	if not is_running: return "STOPPED"
	return "UNKNOWN_EXIT" # Should not happen

# ----------------------------------------------------------------------
# SCOPING HELPERS
# ----------------------------------------------------------------------
func push_scope() -> void:
	environment_stack.append({})

func pop_scope() -> void:
	if environment_stack.size() > 0:
		environment_stack.pop_back()
	else:
		push_error("Scope stack is empty; cannot pop.")

func set_var(var_name: String, value: Variant) -> void:
	if environment_stack.size() == 0:
		report_error(current_line-1,"No scope available to store variable '%s'." % var_name)
		return
	environment_stack[environment_stack.size() - 1][var_name] = value

func get_var(var_name: String) -> Variant:
	for i in range(environment_stack.size() - 1, -1, -1):
		if environment_stack[i].has(var_name):
			return environment_stack[i][var_name]
	report_error(current_line-1,"Variable '%s' not found in any scope." % var_name)
	return null

# ----------------------------------------------------------------------
# STATEMENT PARSING
# ----------------------------------------------------------------------
# Returns a string from _interpret_line:
# "MOVE" => indicates we did a move statement (requires yield)
# "WAIT" => indicates we did a wait statement (has its own await)
# "NONE" => normal or control statement handled
# "ERROR" => if there's an error
# "RETURN" => if we're returning from a function

func _interpret_line(line: String, indent_level: int) -> String:
	# --- Block Keywords First ---
	if line.begins_with("if ") and line.ends_with(":"):
		return await _handle_if_statement(line, indent_level)
	elif line.begins_with("elif ") and line.ends_with(":"): # <<< Moved UP
		return await _handle_elif_statement(line, indent_level)
	elif line == "else:": # Exact match for else <<< Moved UP
		return await _handle_else_statement(line, indent_level)
	elif line.begins_with("for ") and line.ends_with(":"):
		return await _handle_for_loop(line, indent_level)
	elif line.begins_with("while ") and line.ends_with(":"):
		return await _handle_while_loop(line, indent_level)
	# NOTE: 'func' is handled directly in _run_interpreter to skip blocks

	# --- Declaration / Return ---
	elif line.begins_with("var "):
		var result_ok = _interpret_var_declaration(line)
		return "NONE" if result_ok else "ERROR"
	elif line.begins_with("return"): # Handle return keyword
		# Optional: Add logic here to parse a return value if needed
		return "RETURN"

	# --- Specific Known Command Functions ---
	elif line.begins_with("gas("):
		var ok = await _interpret_gas_statement(line)
		return "MOVE" if ok else "ERROR" # Assuming gas() should yield like movement
	elif line.begins_with("brake("):
		var ok = await _interpret_brake_statement(line)
		return "NONE" if ok else "ERROR" # Brake might or might not need yield depending on await
	elif line.begins_with("turnleft("):
		var ok = await _interpret_turnleft_statement(line)
		return "MOVE" if ok else "ERROR"
	elif line.begins_with("turnright("):
		var ok = await _interpret_turnright_statement(line)
		return "MOVE" if ok else "ERROR"
	elif line.begins_with("pickup("):
		# Assuming pickup might have an animation/await later
		var ok = _interpret_pickup_statement(line)
		return "MOVE" if ok else "ERROR" # Tentative: Treat as move for now
	elif line.begins_with("dropoff("):
		# Assuming dropoff might have an animation/await later
		var ok = _interpret_dropoff_statement(line)
		return "MOVE" if ok else "ERROR" # Tentative: Treat as move for now
	# Backward compatibility calls (if needed, keep them here)
	elif line.begins_with("deliver("): # ... etc ...
		var ok = _interpret_dropoff_statement(line.replace("deliver(", "dropoff("))
		return "MOVE" if ok else "ERROR"
	elif line.begins_with("pick_up("): # ... etc ...
		var ok = _interpret_pickup_statement(line.replace("pick_up(", "pickup("))
		return "MOVE" if ok else "ERROR"
	elif line.begins_with("drop_off("): # ... etc ...
		var ok = _interpret_dropoff_statement(line.replace("drop_off(", "dropoff("))
		return "MOVE" if ok else "ERROR"

	# --- Assignment ---
	# Check for '=' ONLY if it's not part of a keyword line already handled
	elif "=" in line:
		# We already handled var, if, elif, while, for lines above.
		# This should primarily catch variable re-assignment.
		var result_ok = _interpret_assignment(line)
		return "NONE" if result_ok else "ERROR"

	# --- Generic Function Call (User-defined or potentially built-ins not listed above) ---
	# Check for parentheses AFTER specific keywords/commands
	elif "(" in line and ")" in line:
		# This should now catch user function calls like my_func()
		# Or potentially built-ins like checkleft() IF they were called standalone on a line
		# (Standalone check calls usually don't make sense, they are used in conditions)
		# Let's assume this is for user-defined functions for now.
		var result_ok = await _interpret_function_call(line)
		return "NONE" if result_ok else "ERROR"

	# --- Standalone Check Functions (Less common, but maybe for debugging?) ---
	# If check functions are ONLY used in conditions, these checks might be redundant
	# elif line.begins_with("checkleft(") or line.begins_with("not checkleft("):
	#     var result = await _interpret_check_function(line, "checkleft") # Needs this function if standalone calls are allowed
	#     return "NONE" if result != null else "ERROR"
	# elif line.begins_with("checkright(") # ... etc ...
	# elif line.begins_with("checkfront(") # ... etc ...

	# --- Unrecognized Statement ---
	else:
		report_error(current_line-1,"Unrecognized statement on line: %s" % line)
		# Decide if this should be an error or just skipped
		return "NONE" # Treat as skippable for now, maybe return "ERROR"?

# New function to interpret brake() statement
func _interpret_brake_statement(line: String) -> bool:
	var inside = _extract_between(line, "brake(", ")").strip_edges()
	if inside.length() > 0:
		report_error(current_line-1,"brake() doesn't take any parameters.")
		return false

	if player:
		player.brake() # This now awaits tile_reached internally in the player func
		await player.tile_reached # Wait for the signal from player.brake()
		if not is_running:
			push_error("Interpreter stopped during brake() await.")
			return false
		return true
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false

# This helper method for wait() is no longer needed
# We're removing the wait function entirely

# The wait() function is removed

# Function to interpret dropoff() statement
func _interpret_dropoff_statement(line: String) -> bool:
	# dropoff() takes no parameters
	var inside = _extract_between(line, "dropoff(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		report_error(current_line-1,"dropoff() doesn't take any parameters.")
		return false
		
	if player:
		return player.dropoff()  # Call the dropoff function
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false

func _handle_for_loop(line: String, indent_level: int) -> String:
	# e.g., "for i in range(3):" or "for i in range(1, 5):" etc.
	var stripped = line.strip_edges()
	var after_for = stripped.substr(4, stripped.length() - 5).strip_edges() # remove "for " and ":"

	if " in range(" in after_for:
		var pieces = after_for.split(" in range(", true, 1)
		if pieces.size() != 2:
			report_error(current_line-1,"Invalid for syntax: %s" % line)
			return "ERROR"

		var var_name = pieces[0].strip_edges()
		var range_str_raw = pieces[1].strip_edges()
		if not range_str_raw.ends_with(")"):
			report_error(current_line-1,"Invalid range syntax (missing closing parenthesis?): %s" % line)
			return "ERROR"
		var range_str = range_str_raw.substr(0, range_str_raw.length() - 1) # Remove trailing ')'

		var range_args_str = range_str.split(",")
		var range_args_int = []
		for arg_str in range_args_str:
			var val = _parse_value(arg_str.strip_edges()) # Use parse_value to handle variables in range()
			if val is int:
				range_args_int.append(val)
			else:
				report_error(current_line-1,"Range arguments must evaluate to integers: '%s' in %s" % [arg_str, line])
				return "ERROR"

		var start = 0
		var end = 0
		var step = 1

		if range_args_int.size() == 1:
			end = range_args_int[0]
		elif range_args_int.size() == 2:
			start = range_args_int[0]
			end = range_args_int[1]
		elif range_args_int.size() == 3:
			start = range_args_int[0]
			end = range_args_int[1]
			step = range_args_int[2]
			if step == 0:
				report_error(current_line-1,"Range step cannot be zero: %s" % line)
				return "ERROR"
		else:
			report_error(current_line-1,"Invalid number of range arguments: %s" % line)
			return "ERROR"

		var block_start = current_line
		var block_end = _find_block_end(block_start, indent_level + STANDARD_INDENT_STEP) # Use constant for finding end

		var i = start
		while is_running and ((step > 0 and i < end) or (step < 0 and i > end)):
			push_scope()
			set_var(var_name, i)
			current_line = block_start
			# FIX: Use STANDARD_INDENT_STEP
			await _run_interpreter(indent_level + STANDARD_INDENT_STEP) # Recursive call for the block

			# Check if execution was stopped during the awaited block
			if not is_running:
				pop_scope() # Ensure scope cleanup even if stopped
				return "STOPPED" # Indicate interruption

			pop_scope()
			i += step

		# If the loop finished normally (not stopped), set current_line to after the block
		if is_running:
			current_line = block_end
		return "NONE" # Indicate normal loop completion or interruption handled
	else:
		report_error(current_line-1,"Unsupported for loop syntax (only 'in range()' supported): %s" % line)
		return "ERROR"


func _find_end_of_if_elif_else_chain(start_search_line: int, base_indent: int) -> int:
	var line_idx = start_search_line
	while line_idx < code_lines.size():
		var line_full = code_lines[line_idx]
		var line = line_full.strip_edges()
		# Skip empty lines when checking indentation
		if line == "":
			line_idx += 1
			continue

		var indent = _count_indent(line_full)

		if indent == base_indent:
			if line.begins_with("elif ") and line.ends_with(":"):
				# Found an elif, need to skip its block and continue searching after it
				var elif_block_end = _find_block_end(line_idx + 1, base_indent + 1)
				line_idx = elif_block_end # Start searching again right after the elif block
				continue # Continue the while loop from the new position
			elif line == "else:":
				# Found an else, need to skip its block. The chain ends after this block.
				var else_block_end = _find_block_end(line_idx + 1, base_indent + 1)
				line_idx = else_block_end # The chain ends here
				break # Exit the while loop
			else:
				# Found a line at the same indent that is not elif/else, chain ends *before* this line
				break # Exit the while loop, line_idx is the start of the next statement
		elif indent < base_indent:
			# Found a line with less indent, chain definitely ends *before* this line
			break # Exit the while loop
		else: # indent > base_indent
			# This indicates an improperly indented line after a block, or an empty line.
			# Let's treat it as the end of the chain for safety, though it might indicate a syntax error.
			report_error(current_line-1,"Unexpected indentation level at line %d, ending if/elif/else chain search." % line_idx)
			break

	return line_idx # Returns the index of the first line *after* the entire chain



func _handle_if_statement(line: String, indent_level: int) -> String:
	var stripped = line.strip_edges()
	var after_if = stripped.substr(3, stripped.length() - 4).strip_edges() # remove "if " and ":"
	var cond_str = after_if

	var block_start = current_line
	# Calculate expected indent for the block content
	var expected_block_indent = indent_level + STANDARD_INDENT_STEP
	var block_end = _find_block_end(block_start, expected_block_indent)

	# Evaluate the condition using the robust evaluator
	var condition_result = _eval_condition(cond_str)
	if not is_running: return "STOPPED" # Condition evaluation itself shouldn't stop, but check anyway

	if condition_result:
		# Execute the if block
		push_scope()
		current_line = block_start
		# FIX: Use calculated expected_block_indent
		await _run_interpreter(expected_block_indent)
		# Check if stopped during the block execution
		if not is_running:
			pop_scope()
			return "STOPPED"
		pop_scope()

		# If we executed the 'if' block, we need to skip past all subsequent elif/else blocks
		current_line = _find_end_of_if_elif_else_chain(block_end, indent_level)
	else:
		# Condition was false, skip the if block's code
		current_line = block_end
		# The main interpreter loop will naturally proceed to the next line,
		# which might be an elif, else, or the statement after the whole structure.

	return "NONE"


# New function to handle elif statements
func _handle_elif_statement(line: String, indent_level: int) -> String:
	# This function should only be entered by the main loop if the preceding if/elif conditions were false.
	var stripped = line.strip_edges()
	var after_elif = stripped.substr(5, stripped.length() - 6).strip_edges() # remove "elif " and ":"
	var cond_str = after_elif

	var block_start = current_line
	# Calculate expected indent for the block content
	var expected_block_indent = indent_level + STANDARD_INDENT_STEP
	var block_end = _find_block_end(block_start, expected_block_indent)

	# Evaluate the condition for this elif
	var condition_result = _eval_condition(cond_str)
	if not is_running: return "STOPPED"

	if condition_result:
		# Execute the elif block
		push_scope()
		current_line = block_start
		# FIX: Use calculated expected_block_indent
		await _run_interpreter(expected_block_indent)
		# Check if stopped during execution
		if not is_running:
			pop_scope()
			return "STOPPED"
		pop_scope()

		# If we executed the 'elif' block, skip past any remaining elif/else blocks
		current_line = _find_end_of_if_elif_else_chain(block_end, indent_level)
	else:
		# Condition was false, skip the elif block's code
		current_line = block_end
		# Let the main loop proceed to check the next line (could be another elif or else)

	return "NONE"


func _handle_else_statement(line: String, indent_level: int) -> String:
	# This function should only be entered if all preceding if/elif conditions were false.
	var block_start = current_line
	# Calculate expected indent for the block content
	var expected_block_indent = indent_level + STANDARD_INDENT_STEP
	var block_end = _find_block_end(block_start, expected_block_indent)

	# Execute the else block unconditionally (since we got here)
	push_scope()
	current_line = block_start
	# FIX: Use calculated expected_block_indent
	await _run_interpreter(expected_block_indent)
	# Check if stopped during execution
	if not is_running:
		pop_scope()
		return "STOPPED"
	pop_scope()

	# After executing the else block, the if/elif/else structure is finished.
	# Set current_line to the line immediately after the else block.
	current_line = block_end

	return "NONE"


# New function to handle the check functions
func _interpret_check_function(line: String, func_name: String) -> Variant:
	var has_not = false
	var start_index = 0
	
	# Check if there's a "not " prefix
	if line.begins_with("not "):
		has_not = true
		start_index = 4  # Skip "not "
	
	# Extract the function name and parameter
	var func_call = line.substr(start_index)
	var param_start = func_call.find("(") + 1
	var param_end = func_call.find(")")
	
	if param_start <= 0 or param_end <= param_start:
		report_error(current_line-1,"Invalid check function syntax: " + line)
		return null
	
	var check_type = func_call.substr(param_start, param_end - param_start).strip_edges()
	
	# Parse the check type parameter
	var check_value = _parse_value(check_type)
	
	# Call the appropriate check function on the player
	if player:
		var result: bool
		match func_name:
			"checkleft":
				result = player.checkleft(check_value)
			"checkright":
				result = player.checkright(check_value)
			"checkfront":
				result = player.checkfront(check_value)
			_:
				report_error(current_line-1,"Unknown check function: " + func_name)
				return null
		
		# Apply negation if needed
		if has_not:
			return not result
		else:
			return result
	else:
		report_error(current_line-1,"No player assigned to interpreter")
		return null

func _handle_while_loop(line: String, indent_level: int) -> String:
	var stripped = line.strip_edges()
	var after_while = stripped.substr(6, stripped.length() - 7).strip_edges() # remove "while " and ":"
	var cond_str = after_while

	var block_start = current_line # Line number AFTER the 'while:' line itself
	# Calculate expected indent for the block content
	var expected_block_indent = indent_level + STANDARD_INDENT_STEP
	var block_end = _find_block_end(block_start, expected_block_indent)


	var iteration_limit = 1000 # Keep the safety limit (adjust if needed)
	var iteration_count = 0

	# Evaluate condition *before* the first iteration
	while is_running and iteration_count < iteration_limit and _eval_condition(cond_str):
		# Execute the block
		push_scope()

		# Reset current_line to the start of the block for EACH iteration
		current_line = block_start

		# FIX: Use calculated expected_block_indent
		await _run_interpreter(expected_block_indent) # Execute block contents

		# Check if execution was stopped during the awaited block
		if not is_running:
			pop_scope() # Clean up scope
			return "STOPPED" # Indicate interruption

		pop_scope()
		iteration_count += 1
		# The loop automatically re-evaluates _eval_condition(cond_str) next

	# --- Handle loop termination ---
	if is_running and iteration_count >= iteration_limit:
		report_error(current_line-1,"While loop iteration limit (%d) reached: %s" % [iteration_limit, line])
		report_error(current_line-1,"While loop terminated due to iteration limit.")
		# Make sure is_running is false if we hit the limit and treat as error
		is_running = false
		return "ERROR" # Return ERROR if limit is hit

	# If the loop finished normally (condition became false or stopped externally)
	# set current_line to the end of the block so execution continues after it.
	if is_running: # Only set if not stopped externally
		current_line = block_end
	# else: current_line remains where it was when is_running became false

	return "NONE" # Indicate normal loop completion or handled interruption/error
	
func _interpret_pickup_statement(line: String) -> bool:
	# pickup() takes no parameters
	var inside = _extract_between(line, "pickup(", ")")
	inside = inside.strip_edges()
	
	# Verify no arguments were passed
	if inside.length() > 0:
		report_error(current_line-1,"pickup() doesn't take any parameters.")
		return false
		
	if player:
		return player.pickup()
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false

func _interpret_var_declaration(line: String) -> bool:
	# e.g., "var dir = \"East\""
	var stripped = line.strip_edges()
	var after_var = stripped.substr(4, stripped.length() - 4)
	var pieces = after_var.split("=", true, 1)  # Split only on first =
	if pieces.size() != 2:
		report_error(current_line-1,"Invalid var syntax: %s" % line)
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
		report_error(current_line-1,"Invalid assignment syntax: %s" % line)
		return false
	var var_name = pieces[0].strip_edges()
	var var_value_raw = pieces[1].strip_edges()
	var parsed_value = _parse_value(var_value_raw)
	
	# Check if variable exists first
	if get_var(var_name) == null:
		report_error(current_line-1,"Creating new variable in assignment: %s" % var_name)
	
	set_var(var_name, parsed_value)
	return true

func _interpret_gas_statement(line: String) -> bool:
	# gas() takes no parameters
	var inside = _extract_between(line, "gas(", ")").strip_edges()
	if inside.length() > 0:
		report_error(current_line-1,"gas() doesn't take any parameters. Got: '%s'" % inside)
		return false

	if player:
		print("INTERPRETER: Executing gas()")
		player.gas() # Call the player function
		await player.tile_reached # Wait for the signal
		# Check if interpreter was stopped while waiting
		if not is_running:
			
			push_error("Interpreter stopped during gas() await.")
			return false # Indicate execution should stop propagating
		print("INTERPRETER: Finished gas() await")
		return true # Success
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false

func _interpret_turnleft_statement(line: String) -> bool:
	# turnleft() takes no parameters
	var inside = _extract_between(line, "turnleft(", ")").strip_edges()
	if inside.length() > 0:
		report_error(current_line-1,"turnleft() doesn't take any parameters. Got: '%s'" % inside)
		return false

	if player:
		player.turnleft() # Call the player function (which starts the turn but doesn't await)
		await player.turn_finished # Wait for the signal indicating the turn is complete
		# Check if interpreter was stopped while waiting
		if not is_running:
			report_error(current_line-1,"Interpreter stopped during turnleft() await.")
			return false # Indicate execution should stop propagating
		return true # Success
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false


func _interpret_turnright_statement(line: String) -> bool:
	# turnright() takes no parameters
	var inside = _extract_between(line, "turnright(", ")").strip_edges()
	if inside.length() > 0:
		report_error(current_line-1,"turnright() doesn't take any parameters. Got: '%s'" % inside)
		return false

	if player:
		player.turnright() # Call the player function (starts turn, doesn't await)
		await player.turn_finished # Wait for the signal indicating the turn is complete
		# Check if interpreter was stopped while waiting
		if not is_running:
			report_error(current_line-1,"Interpreter stopped during turnright() await.")
			return false # Indicate execution should stop propagating
		return true # Success
	else:
		report_error(current_line-1,"No player assigned to interpreter.")
		return false


func _interpret_function_call(line: String) -> bool:
	# e.g., "my_function(arg1, arg2)"
	var func_name_end = line.find("(")
	if func_name_end <= 0:
		report_error(current_line-1,"Invalid function call syntax (cannot find '('): %s" % line)
		return false

	var func_name = line.substr(0, func_name_end).strip_edges()
	if not func_name.is_valid_identifier():
		report_error(current_line-1,"Invalid function name: '%s' in line: %s" % [func_name, line])
		return false

	var args_str = _extract_between(line, "(", ")") # Assumes simple params

	if not functions.has(func_name):
		# Could potentially add checks for built-in functions here if needed
		report_error(current_line-1,"Function not found: %s" % func_name)
		return false

	var func_info = functions[func_name]
	var param_names = func_info.params
	var arg_values = []

	# Parse arguments
	if args_str.strip_edges().length() > 0:
		# Basic comma split - might fail with commas inside strings or nested calls
		var arg_strs = args_str.split(",")
		for arg in arg_strs:
			var parsed_arg = _parse_value(arg.strip_edges())
			if parsed_arg == null and arg.strip_edges() != "": # Check if parsing failed
				report_error(current_line-1,"Could not parse argument '%s' for function %s" % [arg.strip_edges(), func_name])
				return false
			arg_values.append(parsed_arg)

	if arg_values.size() != param_names.size():
		report_error(current_line-1,"Wrong number of arguments for function %s: expected %d, got %d" % [func_name, param_names.size(), arg_values.size()])
		return false

	# Save current execution position
	var saved_line = current_line

	# Set up function scope with parameters
	push_scope()
	for i in range(param_names.size()):
		if i < arg_values.size(): # Safety check
			set_var(param_names[i], arg_values[i])
		else: # Should not happen if previous size check passed
			report_error(current_line-1,"Internal Error: Argument/Parameter mismatch for %s" % func_name)
			pop_scope()
			return false

	# Calculate expected indent level for the function body
	var func_def_line_idx = func_info.start_line - 1
	var func_def_indent = 0
	if func_def_line_idx >= 0 and func_def_line_idx < code_lines.size():
		# Get indent of the 'func ...:' line itself
		func_def_indent = _count_indent(code_lines[func_def_line_idx])
	else:
		report_error(current_line-1,"Could not determine function definition indent for %s" % func_name)
		# Fallback assumption: function defined at base indent 0
		func_def_indent = 0

	current_line = func_info.start_line
	# FIX: Use calculated function definition indent + STANDARD_INDENT_STEP
	var expected_body_indent = func_def_indent + STANDARD_INDENT_STEP
	var result_status = await _run_interpreter(expected_body_indent) # Execute function body

	# Check if stopped during function execution
	var stopped_or_error = false
	if not is_running or result_status == "STOPPED" or result_status == "ERROR":
		stopped_or_error = true

	# Pop scope regardless of stop/error/return to maintain balance
	pop_scope()
	# Restore caller line number only if execution wasn't stopped prematurely
	if not stopped_or_error:
		current_line = saved_line

	# Return false if stopped or error occurred, true otherwise (even if func returned)
	return not stopped_or_error
# ----------------------------------------------------------------------
# EXPRESSION / CONDITION PARSING
# ----------------------------------------------------------------------
func _eval_condition(cond_str_raw: String) -> bool:
	var cond_str = cond_str_raw.strip_edges()

	# Handle logical OR first (lower precedence)
	var or_parts = _split_logical(cond_str, " or ")
	if or_parts.size() > 1:
		for part in or_parts:
			if _eval_condition(part): # Recursive call for each part
				return true # If any part is true, the OR is true
		return false # If no part was true, the OR is false
	# If split resulted in only one part (or no " or "), fall through to AND/basic evaluation

	# Handle logical AND next (higher precedence relative to OR)
	var and_parts = _split_logical(cond_str, " and ")
	if and_parts.size() > 1:
		for part in and_parts:
			if not _eval_condition(part): # Recursive call for each part
				return false # If any part is false, the AND is false
		return true # If no part was false, the AND is true
	# If split resulted in only one part (or no " and "), fall through to basic evaluation

	# --- If no 'or' or 'and' split occurred, evaluate the simple condition ---

	# Handle negation ("not ...") at the simple condition level
	var negate = false
	var effective_cond_str = cond_str # Already stripped
	if effective_cond_str.begins_with("not "):
		# Make sure it's "not " and not part of a variable name like "notify"
		if effective_cond_str.length() > 4 and effective_cond_str[3] == ' ':
			negate = true
			effective_cond_str = effective_cond_str.substr(4).strip_edges()

	var result = _evaluate_simple_condition(effective_cond_str)

	return not result if negate else result



func _split_logical(text: String, separator: String) -> Array[String]:
	var parts: Array[String] = []
	var current_part = ""
	var paren_level = 0
	var in_string = false
	var string_char = ""
	var i = 0
	while i < text.length():
		var char = text[i]
		var remaining_text = text.substr(i)

		if in_string:
			current_part += char
			if char == string_char:
				in_string = false
		elif char == '"' or char == "'":
			in_string = true
			string_char = char
			current_part += char
		elif char == '(':
			paren_level += 1
			current_part += char
		elif char == ')':
			paren_level -= 1
			current_part += char
		elif paren_level == 0 and not in_string and remaining_text.begins_with(separator):
			# Found separator outside parentheses and strings
			parts.append(current_part.strip_edges()) # Trim edges of the part found
			current_part = ""
			i += separator.length() - 1 # Skip the separator length
		else:
			current_part += char
		i += 1

	parts.append(current_part.strip_edges()) # Add and trim the last part
	# Filter out empty strings that might result from splitting
	return parts.filter(func(part): return part != "")


func _evaluate_simple_condition(cond_str: String) -> bool:
	# First check if this is a function call like checkleft(EDGE)
	# Make sure it's *just* a function call, not part of a comparison
	if cond_str.ends_with(")") and "(" in cond_str and \
	   not (" == " in cond_str or " != " in cond_str or " > " in cond_str or " < " in cond_str or " >= " in cond_str or " <= " in cond_str):
		var evaluated_value = _evaluate_expression(cond_str) # Use the existing expression evaluator
		if evaluated_value is bool:
			return evaluated_value
		else:
			# Allow non-bool return values from check functions to be treated as truthy/falsy
			# Example: if checkleft(PASSENGER): -> true if passenger found, false otherwise
			# Based on the _evaluate_expression logic, check functions already return bools.
			# If they returned something else, this check would need adjustment.
			report_error(current_line-1,"Condition function '%s' did not return a boolean, evaluating truthiness." % cond_str)
			return true if evaluated_value else false

	# Handle standard comparison operators
	var op = ""
	# Order matters: Check >=, <= before >, < to avoid partial matches
	var op_list = [" == ", " != ", " >= ", " <= ", " > ", " < "]
	for potential_op in op_list:
		if potential_op in cond_str:
			# Basic check to avoid matching inside strings (not perfect)
			var op_index = cond_str.find(potential_op)
			var quote_count_before = cond_str.substr(0, op_index).count("\"") + cond_str.substr(0, op_index).count("'")
			if quote_count_before % 2 == 0: # If not inside a string literal
				op = potential_op
				break

	if op != "":
		var parts = cond_str.split(op, true, 1) # Split only on the first occurrence
		if parts.size() == 2:
			var left = _evaluate_expression(parts[0].strip_edges())
			var right = _evaluate_expression(parts[1].strip_edges())
			# Perform comparison safely, checking types for >,<,>=,<=
			match op:
				" == ": return left == right
				" != ": return left != right
				" > ":
					if typeof(left) == typeof(right) and (left is int or left is float): return left > right
					report_error(current_line-1,"Cannot compare '>' on types %s and %s" % [typeof(left), typeof(right)])
					return false
				" < ":
					if typeof(left) == typeof(right) and (left is int or left is float): return left < right
					report_error(current_line-1,"Cannot compare '<' on types %s and %s" % [typeof(left), typeof(right)])
					return false
				" >= ":
					if typeof(left) == typeof(right) and (left is int or left is float): return left >= right
					report_error(current_line-1,"Cannot compare '>=' on types %s and %s" % [typeof(left), typeof(right)])
					return false
				" <= ":
					if typeof(left) == typeof(right) and (left is int or left is float): return left <= right
					report_error(current_line-1,"Cannot compare '<=' on types %s and %s" % [typeof(left), typeof(right)])
					return false
		else:
			report_error(current_line-1,"Invalid comparison format: %s" % cond_str)
			return false

	# If no operators found, evaluate the expression and check its truthiness
	var val = _evaluate_expression(cond_str)
	# Standard GDScript truthiness:
	return true if val else false



# Add a new function to evaluate expressions including function calls
func _evaluate_expression(expr_raw: String) -> Variant:
	var expr = expr_raw.strip_edges()
	# Check if this is a function call
	# Improved check to avoid misinterpreting (a+b) or simple values
	if expr.ends_with(")") and expr.contains("("):
		var func_name_end = expr.find("(")
		# Ensure the part before '(' is a valid identifier (function name)
		# and not something else like an operator or another parenthesis
		if func_name_end > 0:
			var potential_func_name = expr.substr(0, func_name_end).strip_edges()
			if potential_func_name.is_valid_identifier() and not "(" in potential_func_name and not potential_func_name.ends_with(" "):

				var func_name = potential_func_name
				# Extract parameters carefully, respecting potential nested calls or commas in strings
				# For simplicity, using _extract_between, which might fail on complex nesting.
				var param_str = _extract_between(expr, "(", ")") # Assuming simple, non-nested params

				# Handle check functions directly (as they return values used in conditions)
				if func_name in ["checkleft", "checkright", "checkfront"]:
					if not player:
						report_error(current_line-1,"No player assigned to interpreter for check function '%s'" % func_name)
						return null

					# Evaluate the parameter string - it could be a variable OR a keyword like EDGE
					var param_value = _parse_value(param_str.strip_edges()) # Use parse_value to resolve variables/keywords

					# ---> Check if _parse_value failed (returned null) <---
					if param_value == null:
						report_error(current_line-1,"Parameter '%s' for function '%s' evaluated to null. Is it a defined variable or a valid keyword (EDGE, PASSENGER, WALL, DESTINATION)?" % [param_str.strip_edges(), func_name])
						return null # Return null to indicate error evaluating expression

					# ---> Ensure the evaluated type is string before calling player func <---
					if not param_value is String:
						report_error(current_line-1,"Parameter '%s' for function '%s' must evaluate to a String (like 'edge', 'passenger'), but got type %s." % [param_str.strip_edges(), func_name, typeof(param_value)])
						return null # Return null to indicate error

					# Call the actual player function with the validated String parameter
					match func_name:
						"checkleft": return player.checkleft(param_value)
						"checkright": return player.checkright(param_value)
						"checkfront": return player.checkfront(param_value)
					# The match _ should not be reachable due to the 'in' check above
				else:
					# Handle other potential future functions that return values
					report_error(current_line-1,"Unsupported function returning value in expression: %s" % func_name)
					return null
			# Fall through if the text before '(' wasn't a valid identifier
		# Fall through if not identified as a known function call returning a value

	# If not a recognized function call returning a value, use the normal parse value logic
	return _parse_value(expr)


func _parse_value(value_raw: String) -> Variant:
	var trimmed = value_raw.strip_edges()
	if trimmed.is_empty():
		return null # Avoid processing empty strings

	# String literals
	if trimmed.begins_with("\"") and trimmed.ends_with("\""):
		return trimmed.substr(1, trimmed.length() - 2)
	if trimmed.begins_with("'") and trimmed.ends_with("'"):
		return trimmed.substr(1, trimmed.length() - 2)
	# Boolean literals
	if trimmed == "true": return true
	if trimmed == "false": return false
	# Numeric literals
	if trimmed.is_valid_int(): return int(trimmed)
	if trimmed.is_valid_float(): return float(trimmed)

	# ---> ** ADDED: Check for known keywords BEFORE variable lookup ** <---
	match trimmed.to_upper(): # Check case-insensitively
		"PASSENGER": return "passenger" # Return the lowercase string expected by player
		"DESTINATION": return "destination"
		"EDGE": return "edge"
		"WALL": return "wall"
		# Add any other keywords you might need here

	# Handle simple arithmetic (NO parentheses support, basic left-to-right for +,- and *,/)
	# (Existing basic arithmetic logic here - keep as is or improve if needed)
	if " + " in trimmed:
		var parts = trimmed.split(" + ", true, 1)
		if parts.size() == 2:
			var left = _parse_value(parts[0]) # Recursive call
			var right = _parse_value(parts[1]) # Recursive call
			if left != null and right != null:
				# Try basic variant addition, handle potential errors if types mismatch severely
				var result = left + right
				return result
	if " - " in trimmed:
		var parts = trimmed.split(" - ", true, 1)
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			if left != null and right != null and (left is int or left is float) and (right is int or right is float): return left - right
	if " * " in trimmed:
		var parts = trimmed.split(" * ", true, 1)
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			if left != null and right != null and (left is int or left is float) and (right is int or right is float): return left * right
	if " / " in trimmed:
		var parts = trimmed.split(" / ", true, 1)
		if parts.size() == 2:
			var left = _parse_value(parts[0])
			var right = _parse_value(parts[1])
			if left != null and right != null and (left is int or left is float) and (right is int or right is float):
				if right == 0.0 or right == 0:
					report_error(current_line-1,"Division by zero: %s" % value_raw)
					return null # Indicate error
				# Ensure float division if either operand is float
				return float(left) / float(right)

	# If none of the above, NOW assume it's a variable name
	var var_value = get_var(trimmed)
	if var_value == null:
		# Variable not found and it wasn't a literal or keyword
		report_error(current_line-1,"Identifier '%s' not found as variable, literal, or keyword." % trimmed)
		# Return null explicitly to signify it couldn't be parsed/found
		return null

	return var_value


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
