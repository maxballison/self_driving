extends Resource
class_name CodeEditorTheme

# Create a theme resource for the code editor
static func create_theme() -> Theme:
	var theme = Theme.new()
	
	# Panel styles
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.18)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.35)
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 5
	theme.set_stylebox("panel", "Panel", panel_style)
	
	# Title bar style
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.2, 0.2, 0.25)
	title_style.border_width_left = 1
	title_style.border_width_top = 1
	title_style.border_width_right = 1
	title_style.border_color = Color(0.3, 0.3, 0.35)
	title_style.corner_radius_top_left = 5
	title_style.corner_radius_top_right = 5
	theme.set_stylebox("titlebar", "Panel", title_style)
	
	# Editor container style
	var editor_style = StyleBoxFlat.new()
	editor_style.bg_color = Color(0.12, 0.12, 0.15)
	editor_style.border_width_left = 1
	editor_style.border_width_top = 1
	editor_style.border_width_right = 1
	editor_style.border_width_bottom = 1
	editor_style.border_color = Color(0.25, 0.25, 0.3)
	theme.set_stylebox("editor", "Panel", editor_style)
	
	# Button normal
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0.25, 0.25, 0.3)
	button_normal.border_width_left = 1
	button_normal.border_width_top = 1
	button_normal.border_width_right = 1
	button_normal.border_width_bottom = 1
	button_normal.border_color = Color(0.35, 0.35, 0.4)
	button_normal.corner_radius_top_left = 3
	button_normal.corner_radius_top_right = 3
	button_normal.corner_radius_bottom_right = 3
	button_normal.corner_radius_bottom_left = 3
	theme.set_stylebox("normal", "Button", button_normal)
	
	# Button hover
	var button_hover = button_normal.duplicate()
	button_hover.bg_color = Color(0.3, 0.3, 0.35)
	theme.set_stylebox("hover", "Button", button_hover)
	
	# Button pressed
	var button_pressed = button_normal.duplicate()
	button_pressed.bg_color = Color(0.2, 0.2, 0.25)
	theme.set_stylebox("pressed", "Button", button_pressed)
	
	# Button disabled
	var button_disabled = button_normal.duplicate()
	button_disabled.bg_color = Color(0.2, 0.2, 0.2)
	button_disabled.border_color = Color(0.25, 0.25, 0.3)
	theme.set_stylebox("disabled", "Button", button_disabled)
	
	# Button panel
	var button_panel = StyleBoxFlat.new()
	button_panel.bg_color = Color(0.17, 0.17, 0.2)
	button_panel.border_width_top = 1
	button_panel.border_color = Color(0.25, 0.25, 0.3)
	theme.set_stylebox("panel", "ButtonPanel", button_panel)
	
	# TextEdit style
	var textedit_style = StyleBoxFlat.new()
	textedit_style.bg_color = Color(0.12, 0.12, 0.15)
	textedit_style.border_width_left = 1
	textedit_style.border_width_top = 1
	textedit_style.border_width_right = 1
	textedit_style.border_width_bottom = 1
	textedit_style.border_color = Color(0.25, 0.25, 0.3)
	textedit_style.corner_radius_top_left = 0
	textedit_style.corner_radius_top_right = 0
	textedit_style.corner_radius_bottom_right = 0
	textedit_style.corner_radius_bottom_left = 0
	theme.set_stylebox("normal", "TextEdit", textedit_style)
	
	# Line counter style
	var line_counter_style = textedit_style.duplicate()
	line_counter_style.bg_color = Color(0.14, 0.14, 0.17)
	theme.set_stylebox("normal", "RichTextLabel", line_counter_style)
	
	# Set fonts
	var font = SystemFont.new()
	font.font_names = ["JetBrains Mono", "Consolas", "Courier New", "DejaVu Sans Mono"]
	font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	
	theme.set_font("font", "TextEdit", font)
	theme.set_font("normal_font", "RichTextLabel", font)
	theme.set_font("font", "Label", font)
	theme.set_font("font", "Button", font)
	
	theme.set_font_size("font_size", "TextEdit", 20)
	theme.set_font_size("normal_font_size", "RichTextLabel", 20)
	theme.set_font_size("font_size", "Label", 16)
	theme.set_font_size("font_size", "Button", 16)
	
	# Set colors
	theme.set_color("font_color", "TextEdit", Color(0.9, 0.9, 0.9))
	theme.set_color("default_color", "RichTextLabel", Color(0.9, 0.9, 0.9))
	theme.set_color("font_color", "Label", Color(0.9, 0.9, 0.9))
	theme.set_color("font_color", "Button", Color(0.9, 0.9, 0.9))
	theme.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	
	# Cursor and selection colors
	theme.set_color("caret_color", "TextEdit", Color(0.9, 0.9, 0.9))
	theme.set_color("selection_color", "TextEdit", Color(0.3, 0.4, 0.6, 0.5))
	theme.set_color("current_line_color", "TextEdit", Color(0.2, 0.2, 0.25))
	
	return theme

# Apply the theme to a specific code editor instance
static func apply_theme(editor: Control) -> void:
	editor.theme = create_theme()
	
	# Apply panel background
	if editor.has_node("PanelBackground"):
		editor.get_node("PanelBackground").add_theme_stylebox_override("panel", editor.theme.get_stylebox("panel", "Panel"))
	
	# Custom styling for specific elements
	if editor.has_node("TitleBar"):
		editor.get_node("TitleBar").add_theme_stylebox_override("panel", editor.theme.get_stylebox("titlebar", "Panel"))
	
	# Editor container styling
	if editor.has_node("EditorContainer"):
		editor.get_node("EditorContainer").add_theme_stylebox_override("panel", editor.theme.get_stylebox("editor", "Panel"))
	
	# Style the run button with a green color scheme
	if editor.has_node("ButtonPanel/RunButton"):
		var run_button = editor.get_node("ButtonPanel/RunButton")
		
		var run_normal = StyleBoxFlat.new()
		run_normal.bg_color = Color(0.2, 0.5, 0.2)
		run_normal.border_width_left = 1
		run_normal.border_width_top = 1
		run_normal.border_width_right = 1
		run_normal.border_width_bottom = 1
		run_normal.border_color = Color(0.3, 0.6, 0.3)
		run_normal.corner_radius_top_left = 3
		run_normal.corner_radius_top_right = 3
		run_normal.corner_radius_bottom_right = 3
		run_normal.corner_radius_bottom_left = 3
		
		var run_hover = run_normal.duplicate()
		run_hover.bg_color = Color(0.25, 0.6, 0.25)
		
		var run_pressed = run_normal.duplicate()
		run_pressed.bg_color = Color(0.15, 0.4, 0.15)
		
		run_button.add_theme_stylebox_override("normal", run_normal)
		run_button.add_theme_stylebox_override("hover", run_hover)
		run_button.add_theme_stylebox_override("pressed", run_pressed)
	
	# Button panel styling
	if editor.has_node("ButtonPanel"):
		var button_panel = editor.get_node("ButtonPanel")
		button_panel.add_theme_stylebox_override("panel", editor.theme.get_stylebox("panel", "ButtonPanel"))
	
	# Customize resize handle
	if editor.has_node("ResizeHandle"):
		var resize_handle = editor.get_node("ResizeHandle")
		resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
