extends Control
class_name TutorialWindow

# Core components - we'll check these manually to avoid null references
var title_bar = null
var title_label = null
var close_button = null
var message_container = null
var message_text = null
var next_button = null
var resize_handle = null

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

# Dragging and resizing
var dragging: bool = false
var resizing: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var last_valid_size: Vector2 = Vector2.ZERO

# Signal for level-specific events
signal tutorial_completed

func _ready() -> void:
	print("TutorialWindow _ready() - Setting up UI components manually")
	
	# Initialize UI components manually instead of using @onready
	title_bar = get_node_or_null("TitleBar")
	if title_bar:
		title_label = title_bar.get_node_or_null("TitleLabel")
		close_button = title_bar.get_node_or_null("CloseButton") 
	
	message_container = get_node_or_null("MessageContainer")
	if message_container:
		message_text = message_container.get_node_or_null("RichTextLabel")
	
	var button_panel = get_node_or_null("ButtonPanel")
	if button_panel:
		next_button = button_panel.get_node_or_null("NextButton")
	
	resize_handle = get_node_or_null("ResizeHandle")
	
	# Print node information for debugging
	print("UI Components:")
	print("- title_bar: ", "Found" if title_bar else "MISSING")
	print("- title_label: ", "Found" if title_label else "MISSING")
	print("- close_button: ", "Found" if close_button else "MISSING")
	print("- message_container: ", "Found" if message_container else "MISSING")
	print("- message_text: ", "Found" if message_text else "MISSING")
	print("- next_button: ", "Found" if next_button else "MISSING")
	print("- resize_handle: ", "Found" if resize_handle else "MISSING")
	
	# Set window title if possible
	if title_label:
		title_label.text = title
	
	# Configure appearance
	last_valid_size = size
	
	# Apply theme
	TutorialTheme.apply_theme(self)
	
	# Initialize with default tutorial message
	if current_messages.size() == 0:
		current_messages = ["Welcome to the tutorial! This text should be visible.\n\nClick Next to continue."]
		start_typing_message()
	
	# Debug print
	print("TutorialWindow initialized with size: ", size)

# Safe setter for message text
func safe_set_text(text: String) -> void:
	if message_text != null:
		message_text.text = text
	else:
		# Try to get the node again
		if has_node("MessageContainer/RichTextLabel"):
			message_text = get_node("MessageContainer/RichTextLabel")
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
			emit_signal("tutorial_completed")
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
		emit_signal("tutorial_completed")
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
	if is_typing:
		safe_set_button_text("Skip")
	else:
		if current_message_index < current_messages.size() - 1:
			safe_set_button_text("Next")
		else:
			safe_set_button_text("Got it!")
	
	safe_set_button_disabled(current_messages.size() == 0)

func _on_level_switched() -> void:
	# This will be called when the level changes
	var level_manager = get_node_or_null("/root/Main/LevelManager")
	if level_manager:
		var level_path = level_manager.current_level_instance.scene_file_path
		load_tutorial_for_level(level_path)
		print("Level switched: ", level_path)

func load_tutorial_for_level(level_path: String) -> void:
	# Get the tutorial messages from the TutorialManagers singleton
	# Direct access to the autoloaded singleton
	if TutorialManagers:
		var messages = TutorialManagers.get_messages_for_level(level_path)
		set_tutorial_messages(messages)
		visible = true
		print("Loaded tutorial for level: ", level_path)
	else:
		# Fallback if TutorialManagers is not available
		var default_message = ["Level: " + level_path.get_file(), 
							  "Use the code editor to write commands like:\n[code]drive()[/code]"]
		set_tutorial_messages(default_message)
		visible = true
		print("TutorialManagers singleton not found, using default message")
