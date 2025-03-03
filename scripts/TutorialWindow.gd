extends Control
class_name TutorialWindow

# Core components
@onready var title_bar = $TitleBar
@onready var title_label = $TitleBar/TitleLabel
@onready var close_button = $TitleBar/CloseButton
@onready var message_container = $MessageContainer
@onready var message_text = $MessageContainer/RichTextLabel
@onready var next_button = $ButtonPanel/NextButton
@onready var resize_handle = $ResizeHandle

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
	# Set window title
	title_label.text = title
	
	# Connect signals
	# The signals are now connected in the scene file
	
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
					message_text.text = current_messages[current_message_index]
					typing_index = current_messages[current_message_index].length()
					is_typing = false
					skip_typing = false
					print("Displayed full message: ", message_text.text)
				else:
					# Otherwise add one character at a time
					typing_index += 1
					message_text.text = current_messages[current_message_index].substr(0, typing_index)
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
			print("Dragging window to: ", position)
		elif resizing:
			var new_size = last_valid_size + event.relative
			if new_size.x >= min_size.x and new_size.y >= min_size.y:
				size = new_size
				last_valid_size = new_size
				print("Resizing window to: ", size)

func _on_title_bar_gui_input(event: InputEvent) -> void:
	# Handle dragging via the title bar
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = get_global_mouse_position() - position
				print("Started dragging from title bar")
			else:
				dragging = false
				print("Stopped dragging")

func _on_resize_handle_gui_input(event: InputEvent) -> void:
	# Handle resizing via the resize handle
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				resizing = true
				last_valid_size = size
				print("Started resizing")
			else:
				resizing = false
				print("Stopped resizing")

func _on_close_button_pressed() -> void:
	visible = false
	print("Closed tutorial window")

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
			print("Moving to next message: ", current_message_index)
		else:
			# No more messages
			emit_signal("tutorial_completed")
			_update_button_state()
			print("Tutorial completed")

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
		message_text.text = ""
	_update_button_state()

func start_typing_message() -> void:
	if current_message_index < current_messages.size():
		typing_index = 0
		typing_timer = 0.0
		is_typing = true
		skip_typing = false
		message_text.text = ""
		print("Starting to type message: ", current_message_index)
		_update_button_state()

func _update_button_state() -> void:
	if is_typing:
		next_button.text = "Skip"
	else:
		if current_message_index < current_messages.size() - 1:
			next_button.text = "Next"
		else:
			next_button.text = "Got it!"
	
	next_button.disabled = (current_messages.size() == 0)

func _on_level_switched() -> void:
	# This will be called when the level changes
	var level_manager = get_node_or_null("/root/Main/LevelManager")
	if level_manager and level_manager.current_level_instance:
		var level = level_manager.current_level_instance
		var level_path = level_manager.current_level_instance.scene_file_path
		load_tutorial_for_level(level_path)
		print("Level switched: ", level_path)

func load_tutorial_for_level(level_path: String) -> void:
	# Get the tutorial messages from the TutorialManager
	var tutorial_manager = get_node_or_null("/root/TutorialManager")
	if tutorial_manager:
		var messages = tutorial_manager.get_messages_for_level(level_path)
		set_tutorial_messages(messages)
		visible = true
		print("Loaded tutorial for level: ", level_path)
	else:
		# Fallback if TutorialManager is not available
		var default_message = ["Level: " + level_path.get_file(), 
							  "Use the code editor to write commands like:\n[code]move(\"East\")[/code]"]
		set_tutorial_messages(default_message)
		visible = true
		print("TutorialManager not found, using default message")
