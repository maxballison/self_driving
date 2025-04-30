extends Control
class_name TutorialWindow

# Tab references
var tabs = null
var tutorial_tab = null
var docs_tab = null

# Core components
var title_bar = null
var title_label = null
var close_button = null
var message_container = null
var message_text = null
var next_button = null
var back_button = null  # New back button
var resize_handle = null

# Documentation components
var function_list = null
var function_description = null

# Window settings
@export var title: String = "Tutorial"
@export var min_size: Vector2 = Vector2(350, 250)
@export var default_font_size: int = 18

# Typing effect settings
@export var typing_speed: float = 0.03  # Time between characters
@export var punctuation_pause_multiplier: float = 3.0  # Longer pauses after punctuation

# Message management
var current_messages: Array = []
var current_message_index: int = 0
var is_typing: bool = false
var typing_index: int = 0
var typing_timer: float = 0.0
var skip_typing: bool = false

# Function documentation
var available_functions = []
var current_function_index = -1

# Dragging and resizing
var dragging: bool = false
var resizing: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var last_valid_size: Vector2 = Vector2.ZERO

# Signal for level-specific events
signal message_sequence_finished

func _ready() -> void:
	print("TutorialWindow _ready() - Setting up UI components")
	
	# Find tab system
	tabs = get_node_or_null("TabContainer")
	if tabs:
		tutorial_tab = tabs.get_node_or_null("Tutorial")
		docs_tab = tabs.get_node_or_null("Documentation")
	
	# Initialize UI components for tutorial tab
	if tutorial_tab:
		message_container = tutorial_tab.get_node_or_null("MessageContainer")
		if message_container:
			message_text = message_container.get_node_or_null("RichTextLabel")
	else:
		# Fallback to direct path
		message_text = get_node_or_null("TabContainer/Tutorial/MessageContainer/RichTextLabel")
	
	# Initialize UI components for docs tab
	if docs_tab:
		function_list = docs_tab.get_node_or_null("HSplitContainer/FunctionList")
		function_description = docs_tab.get_node_or_null("HSplitContainer/FunctionDescription/RichTextLabel")
	else:
		# Fallback to direct path
		function_list = get_node_or_null("TabContainer/Documentation/HSplitContainer/FunctionList")
		function_description = get_node_or_null("TabContainer/Documentation/HSplitContainer/FunctionDescription/RichTextLabel")
	
	print("Function list found:", function_list != null)
	print("Function description found:", function_description != null)
	
	# Other UI components
	title_bar = get_node_or_null("TitleBar")
	if title_bar:
		title_label = title_bar.get_node_or_null("TitleLabel")
		close_button = title_bar.get_node_or_null("CloseButton") 
	
	back_button = get_node_or_null("ButtonPanel/BackButton")
	next_button = get_node_or_null("ButtonPanel/NextButton")
	resize_handle = get_node_or_null("ResizeHandle")
	
	# Set window title if possible
	if title_label:
		title_label.text = title
	
	# Configure appearance
	last_valid_size = size
	
	# Apply theme
	TutorialTheme.apply_theme(self)
	
	# Connect signals for function list
	if function_list:
		if not function_list.is_connected("item_selected", Callable(self, "_on_function_selected")):
			function_list.item_selected.connect(_on_function_selected)
	
	# Initialize with default tutorial message
	if current_messages.size() == 0:
		current_messages = ["Welcome to the tutorial! Click Next to continue."]
		start_typing_message()
	
	# Print debug info
	print("TutorialWindow initialized with size: ", size)

# Helper method to ensure UI references are valid
func ensure_ui_references() -> void:
	print("Ensuring UI references are valid")
	
	# Check message_text
	if message_text == null:
		message_text = get_node_or_null("TabContainer/Tutorial/MessageContainer/RichTextLabel")
		print("Message text found:", message_text != null)
	
	# Check function_list
	if function_list == null:
		function_list = get_node_or_null("TabContainer/Documentation/HSplitContainer/FunctionList")
		print("Function list found:", function_list != null)
	
	# Check function_description
	if function_description == null:
		function_description = get_node_or_null("TabContainer/Documentation/HSplitContainer/FunctionDescription/RichTextLabel")
		print("Function description found:", function_description != null)

# Safe setter for text in message display
func safe_set_text(text: String) -> void:
	if message_text != null:
		message_text.text = text
	else:
		# Try to get the node again with correct path in tab structure
		if has_node("TabContainer/Tutorial/MessageContainer/RichTextLabel"):
			message_text = get_node("TabContainer/Tutorial/MessageContainer/RichTextLabel")
			message_text.text = text
		else:
			push_error("Failed to set text - RichTextLabel not found")

# Safe setter for button text
func safe_set_button_text(text: String) -> void:
	if next_button != null:
		next_button.text = text
	else:
		# Try to get the node again
		if has_node("ButtonPanel/NextButton"):
			next_button = get_node("ButtonPanel/NextButton")
			next_button.text = text
		else:
			push_error("Failed to set button text - NextButton not found")

# Safe setter for button disabled state
func safe_set_button_disabled(disabled: bool) -> void:
	if next_button != null:
		next_button.disabled = disabled
	else:
		# Try to get the node again
		if has_node("ButtonPanel/NextButton"):
			next_button = get_node("ButtonPanel/NextButton")
			next_button.disabled = disabled
		else:
			push_error("Failed to set button disabled state - NextButton not found")

func _process(delta: float) -> void:
	if is_typing:
		typing_timer += delta
		
		var current_char_time = typing_speed
		if typing_index > 0 and typing_index < current_messages[current_message_index].length():
			var prev_char = current_messages[current_message_index][typing_index - 1]
			if prev_char in ['.', '!', '?', ',', ';', ':']:
				current_char_time *= punctuation_pause_multiplier
		
		if typing_timer >= current_char_time or skip_typing:
			typing_timer = 0.0
			
			if typing_index < current_messages[current_message_index].length():
				# If skipping, just display the whole message
				if skip_typing:
					safe_set_text(current_messages[current_message_index])
					typing_index = current_messages[current_message_index].length()
					is_typing = false
					skip_typing = false
					print("Displayed full message")
				else:
					# Otherwise add one character at a time
					typing_index += 1
					safe_set_text(current_messages[current_message_index].substr(0, typing_index))
			else:
				is_typing = false
				_update_button_state()
				print("Finished typing message")

func _gui_input(event: InputEvent) -> void:
	# Handle mouse button events
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_typing:
					skip_typing = true
					print("Skipping typing animation")
			else:
				dragging = false
				resizing = false
	
	# Handle mouse motion for dragging/resizing
	elif event is InputEventMouseMotion:
		if dragging:
			position = get_global_mouse_position() - drag_offset
		elif resizing:
			var new_size = last_valid_size + event.relative
			if new_size.x >= min_size.x and new_size.y >= min_size.y:
				size = new_size
				last_valid_size = new_size

func _on_title_bar_gui_input(event: InputEvent) -> void:
	# Handle dragging via the title bar
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = get_global_mouse_position() - position
			else:
				dragging = false

func _on_resize_handle_gui_input(event: InputEvent) -> void:
	# Handle resizing via the resize handle
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				resizing = true
				last_valid_size = size
			else:
				resizing = false

func _on_close_button_pressed() -> void:
	visible = false

# Handle tab changes
func _on_tab_changed(tab_index: int) -> void:
	print("Tab changed to", tab_index)
	if tab_index == 1:  # Documentation tab
		print("Switching to documentation tab, updating function list")
		update_function_list()

# Update the function list based on current level
func update_function_list() -> void:
	print("Updating function list with", available_functions.size(), "functions")
	
	# Ensure UI references are valid
	ensure_ui_references()
	
	if not function_list:
		print("ERROR: function_list is null!")
		return
	
	function_list.clear()
	current_function_index = -1
	
	# Populate function list
	for i in range(available_functions.size()):
		var func_data = available_functions[i]
		var function_name = func_data.get("name", "Unknown")
		var category = func_data.get("category", "")
		
		# Add category prefix for organization
		var display_text = function_name
		if category != "":
			display_text = "[" + category + "] " + function_name
		
		print("Adding function:", display_text)
		function_list.add_item(display_text)
	
	# Select first item if available
	if function_list.get_item_count() > 0:
		function_list.select(0)
		_on_function_selected(0)
	else:
		print("WARNING: No functions to display!")

# Handle function selection
func _on_function_selected(index: int) -> void:
	if index < 0 or index >= available_functions.size():
		return
	
	current_function_index = index
	var func_data = available_functions[index]
	
	# Build the documentation text
	var doc_text = "[b]" + func_data.get("name", "Unknown") + "[/b]\n\n"
	doc_text += func_data.get("description", "No description available.") + "\n\n"
	
	# Add example if available
	var example = func_data.get("example", "")
	if example != "":
		doc_text += "[b]Example:[/b]\n[code]" + example + "[/code]"
	
	# Display the documentation
	if function_description:
		function_description.text = doc_text

# Set available functions for the current level
func set_available_functions(functions: Array) -> void:
	print("Setting available functions:", functions.size())
	available_functions = functions.duplicate() # Use duplicate to ensure we have a clean copy
	
	# If we're already on the docs tab, update immediately
	if tabs and tabs.current_tab == 1:
		update_function_list()

# Handle back button
func _on_back_button_pressed() -> void:
	print("Back button pressed")
	if current_message_index > 0:
		current_message_index -= 1
		start_typing_message()
		_update_button_state()

func _on_next_button_pressed() -> void:
	print("Next button pressed")
	if is_typing:
		# Skip typing if button pressed during typing
		skip_typing = true
	else:
		# Move to next message
		current_message_index += 1
		if current_message_index < current_messages.size():
			start_typing_message()
		else:
			# No more messages
			emit_signal("message_sequence_finished")
		_update_button_state()

func _on_meta_clicked(meta) -> void:
	# Handle clickable links in tutorial messages
	if meta.begins_with("http"):
		OS.shell_open(meta)
	elif meta.begins_with("command:"):
		# You can add custom commands here
		var command = meta.substr("command:".length())
		execute_command(command)

func execute_command(command: String) -> void:
	# Process custom commands embedded in tutorial text
	# For example: "command:run_code" or "command:show_hint"
	if command == "skip_tutorial":
		emit_signal("message_sequence_finished")
		visible = false
	# Add more commands as needed

func set_tutorial_messages(messages: Array) -> void:
	current_messages = messages
	current_message_index = 0
	if current_messages.size() > 0:
		start_typing_message()
		print("Set tutorial messages: ", messages.size(), " messages")
	else:
		safe_set_text("")
	_update_button_state()

func start_typing_message() -> void:
	if current_message_index < current_messages.size():
		typing_index = 0
		typing_timer = 0.0
		is_typing = true
		skip_typing = false
		safe_set_text("")
		print("Starting to type message: ", current_message_index)
		_update_button_state()

func _update_button_state() -> void:
	# Back button should always be visible but may be disabled
	if back_button:
		back_button.visible = true
		back_button.disabled = current_message_index <= 0
	
	# Next/Skip button behavior
	if next_button:
		if is_typing:
			next_button.text = "Skip"
			next_button.visible = true
		else:
			next_button.text = "Next"
			# Only show next button if there are more messages
			next_button.visible = current_message_index < current_messages.size() - 1
			next_button.disabled = current_messages.size() == 0

func _on_level_switched() -> void:
	# This will be called when the level changes
	var level_manager = get_node_or_null("/root/Main/LevelManager")
	if level_manager and level_manager.current_level_instance:
		var level_path = level_manager.current_level_instance.scene_file_path
		load_tutorial_for_level(level_path)
		print("Level switched: ", level_path)

func load_tutorial_for_level(level_path: String) -> void:
	# Ensure UI references are valid before proceeding
	ensure_ui_references()
	
	# Get the tutorial messages from the TutorialManagers singleton
	if TutorialManagers:
		# Get tutorial messages
		var messages = TutorialManagers.get_messages_for_level(level_path)
		set_tutorial_messages(messages)
		
		# Get available functions
		var functions = TutorialManagers.get_functions_for_level(level_path)
		set_available_functions(functions)
		
		# Show the window and reset to first tab
		visible = true
		if tabs:
			tabs.current_tab = 0
			
		print("Loaded tutorial and functions for level: ", level_path)
	else:
		# Fallback if TutorialManagers is not available
		var default_message = ["Level: " + level_path.get_file(), 
							  "Use the code editor to write commands like:\n[code]drive()[/code]"]
		set_tutorial_messages(default_message)
		set_available_functions([])
		visible = true
		print("TutorialManagers singleton not found, using default message")
