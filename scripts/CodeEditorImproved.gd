extends Control
class_name ImprovedCodeEditor

# Core components
@onready var title_bar = $TitleBar
@onready var title_label = $TitleBar/TitleLabel
@onready var close_button = $TitleBar/CloseButton
@onready var text_edit = $EditorContainer/EditorBox/TextEdit
@onready var run_button = $ButtonPanel/RunButton
@onready var line_counter = $EditorContainer/EditorBox/LineCounter
@onready var resize_handle = $ResizeHandle

# Line restriction settings
@export var max_lines: int = 15
@export var title: String = "Code Editor"
@export var syntax_highlighting: bool = true
@export var run_delay: float = 0.5 # Used by the interpreter

# Editor settings
@export var min_size: Vector2 = Vector2(400, 300)
@export var default_font_size: int = 23

# Reference to the interpreter
@onready var interpreter = get_node("/root/Main/ScriptInterpreter")

# Dragging and resizing
var dragging = false
var resizing = false
var drag_offset = Vector2()
var last_valid_size = Vector2()

# Colors for syntax highlighting
var keyword_color = Color(0.3, 0.6, 1.0)  # Blue for keywords
var function_color = Color(0.9, 0.6, 0.2)  # Orange for functions
var string_color = Color(0.6, 0.9, 0.3)    # Green for strings
var number_color = Color(0.9, 0.4, 0.4)    # Red for numbers
var comment_color = Color(0.5, 0.5, 0.5)   # Gray for comments
var background_color = Color(0.12, 0.12, 0.15) # Dark background
var text_color = Color(0.9, 0.9, 0.9)      # Light text

func _ready() -> void:
	# Set window title
	title_label.text = title
	
	# Connect signals
	run_button.pressed.connect(_on_run_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	text_edit.text_changed.connect(_on_text_changed)
	
	# Configure TextEdit appearance
	_configure_text_edit()
	
	# Ensure proper initial sizing
	last_valid_size = size
	
	# Add some sample code
	if text_edit.text.strip_edges() == "":
		text_edit.text = "# Welcome to the Code Editor\n# Write your code here\n\n"
	
	# Force update line counter
	_update_line_counter()
	CodeEditorTheme.apply_theme(self)

func _configure_text_edit() -> void:
	# Basic editor settings
	text_edit.syntax_highlighter = create_syntax_highlighter() if syntax_highlighting else null
	text_edit.draw_tabs = true
	text_edit.draw_spaces = false
	text_edit.minimap_draw = false
	text_edit.highlight_current_line = true
	text_edit.scroll_smooth = true
	text_edit.scroll_v_scroll_speed = 80
	
	# Ensure TextEdit uses scrollbar instead of expanding
	text_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = SIZE_EXPAND_FILL
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	
	# Set colors
	text_edit.add_theme_color_override("background_color", background_color)
	text_edit.add_theme_color_override("font_color", text_color)
	text_edit.add_theme_color_override("current_line_color", Color(0.2, 0.2, 0.25))
	
	# Set font
	var font = SystemFont.new()
	font.font_names = ["JetBrains Mono", "Consolas", "Courier New", "DejaVu Sans Mono"]
	font.font_italic = false
	font.font_weight = 400
	font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	
	var font_size = default_font_size
	text_edit.add_theme_font_override("font", font)
	text_edit.add_theme_font_size_override("font_size", font_size)
	title_label.add_theme_font_override("font", font)
	title_label.add_theme_font_size_override("font_size", font_size)
	
	# Configure line counter for better alignment
	line_counter.add_theme_font_override("normal_font", font)
	line_counter.add_theme_font_size_override("normal_font_size", font_size)
	line_counter.add_theme_color_override("default_color", Color(0.6, 0.6, 0.6))
	line_counter.add_theme_constant_override("line_separation", 4)
	line_counter.size_flags_vertical = SIZE_EXPAND_FILL
	
	# Force monospace font for line counter
	line_counter.bbcode_enabled = true

func create_syntax_highlighter() -> SyntaxHighlighter:
	var highlighter = CodeHighlighter.new()
	
	# Add keywords
	var keywords = ["var", "func", "if", "else", "for", "in", "while", "return", "and", "or", "not", "true", "false"]
	for keyword in keywords:
		highlighter.add_keyword_color(keyword, keyword_color)
	
	# Add special functions
	var functions = ["move", "range"]
	for func_name in functions:
		highlighter.add_keyword_color(func_name, function_color)
	
	# Set operators
	var operators = ["+", "-", "*", "/", "=", "==", "!=", ">", "<", ">=", "<=", "(", ")", "[", "]", ":", ","]
	for op in operators:
		highlighter.add_color_region(op, op, Color(0.8, 0.8, 0.8), true)
	
	# Set string and comment regions
	highlighter.add_color_region("\"", "\"", string_color, false)
	highlighter.add_color_region("'", "'", string_color, false)
	highlighter.add_color_region("#", "", comment_color, true)
	
	# Set number color
	highlighter.number_color = number_color
	
	return highlighter

func _gui_input(event: InputEvent) -> void:
	# Handle mouse button events (for dragging the entire window)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Give focus to text editor when clicking anywhere on the window
				text_edit.grab_focus()
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
				_update_line_counter()

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

func _on_run_button_pressed() -> void:
	var code = text_edit.text
	if interpreter:
		interpreter.execute_script(code)
	else:
		push_error("ScriptInterpreter not found!")

func _update_line_counter() -> void:
	var lines = text_edit.get_line_count()
	var bbcode_text = ""
	
	# Use monospace tag to ensure fixed-width characters
	bbcode_text += "[code]"
	for i in range(1, max(lines, 1) + 1):
		bbcode_text += str(i) + "\n"
	bbcode_text += "[/code]"
	
	line_counter.text = bbcode_text

func _on_text_changed() -> void:
	_update_line_counter()
	
	# Check for line limit
	var current_lines = text_edit.get_line_count()
	
	if current_lines > max_lines:
		# Store cursor position
		var cursor_column = text_edit.get_caret_column()
		var cursor_line = text_edit.get_caret_line()
		
		# Split text into lines and keep only the first max_lines
		var text_lines = text_edit.text.split("\n")
		text_lines = text_lines.slice(0, max_lines)
		
		# Update the text
		text_edit.text = "\n".join(text_lines)
		
		# Restore cursor within bounds
		cursor_line = min(cursor_line, max_lines - 1)
		cursor_column = min(cursor_column, text_edit.get_line(cursor_line).length())
		text_edit.set_caret_line(cursor_line)
		text_edit.set_caret_column(cursor_column)

func _process(_delta: float) -> void:
	# Keep line counter in sync with text edit scrolling
	if text_edit.get_v_scroll_bar() and text_edit.get_v_scroll_bar().visible:
		var scrollbar = text_edit.get_v_scroll_bar()
		if line_counter.get_v_scroll_bar():
			line_counter.get_v_scroll_bar().value = scrollbar.value
