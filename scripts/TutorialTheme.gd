extends Resource
class_name TutorialTheme

# Apply theme to the tutorial window, inheriting from CodeEditorTheme styling
static func apply_theme(window: Control) -> void:
	# Reuse the base theme from CodeEditorTheme
	window.theme = CodeEditorTheme.create_theme()
	
	# Apply panel background
	if window.has_node("PanelBackground"):
		window.get_node("PanelBackground").add_theme_stylebox_override("panel", window.theme.get_stylebox("panel", "Panel"))
	
	# Apply title bar style
	if window.has_node("TitleBar"):
		var title_bar = window.get_node("TitleBar")
		var title_style = StyleBoxFlat.new()
		title_style.bg_color = Color(0.25, 0.25, 0.3)  # Slightly different from code editor
		title_style.border_width_left = 1
		title_style.border_width_top = 1
		title_style.border_width_right = 1
		title_style.border_color = Color(0.35, 0.35, 0.4)
		title_style.corner_radius_top_left = 5
		title_style.corner_radius_top_right = 5
		title_bar.add_theme_stylebox_override("panel", title_style)
	
	# Apply message container style
	if window.has_node("MessageContainer"):
		var message_container = window.get_node("MessageContainer")
		var message_bg = StyleBoxFlat.new()
		message_bg.bg_color = Color(0.12, 0.12, 0.15)  # Dark background
		message_bg.border_width_left = 1
		message_bg.border_width_top = 1
		message_bg.border_width_right = 1
		message_bg.border_width_bottom = 1
		message_bg.border_color = Color(0.25, 0.25, 0.3)
		message_container.add_theme_stylebox_override("panel", message_bg)
	
	# Style for RichTextLabel
	if window.has_node("MessageContainer/RichTextLabel"):
		var rtl = window.get_node("MessageContainer/RichTextLabel")
		
		# Use a more readable font for tutorial text
		var font = SystemFont.new()
		font.font_names = ["JetBrains Mono", "Consolas", "DejaVu Sans Mono"]
		font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
		rtl.add_theme_font_override("normal_font", font)
		rtl.add_theme_font_size_override("normal_font_size", 16)
		
		# Set text colors
		rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
		rtl.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0))
		rtl.add_theme_color_override("selection_color", Color(0.3, 0.4, 0.6, 0.5))
		
		# Code highlighting in rich text
		rtl.add_theme_font_override("mono_font", font)
		rtl.add_theme_font_size_override("mono_font_size", 14)
		rtl.add_theme_color_override("table_odd_row_bg", Color(0.07, 0.07, 0.1))
		rtl.add_theme_color_override("table_even_row_bg", Color(0.1, 0.1, 0.13))
	
	# Style for button panel
	if window.has_node("ButtonPanel"):
		var button_panel = window.get_node("ButtonPanel") 
		var button_panel_style = StyleBoxFlat.new()
		button_panel_style.bg_color = Color(0.17, 0.17, 0.2)
		button_panel_style.border_width_top = 1
		button_panel_style.border_color = Color(0.25, 0.25, 0.3)
		button_panel.add_theme_stylebox_override("panel", button_panel_style)
	
	# Style for next button
	if window.has_node("ButtonPanel/NextButton"):
		var next_button = window.get_node("ButtonPanel/NextButton")
		
		var next_normal = StyleBoxFlat.new()
		next_normal.bg_color = Color(0.3, 0.5, 0.8)  # Blue button
		next_normal.border_width_left = 1
		next_normal.border_width_top = 1
		next_normal.border_width_right = 1
		next_normal.border_width_bottom = 1
		next_normal.border_color = Color(0.4, 0.6, 0.9)
		next_normal.corner_radius_top_left = 3
		next_normal.corner_radius_top_right = 3
		next_normal.corner_radius_bottom_right = 3
		next_normal.corner_radius_bottom_left = 3
		
		var next_hover = next_normal.duplicate()
		next_hover.bg_color = Color(0.35, 0.55, 0.85)
		
		var next_pressed = next_normal.duplicate()
		next_pressed.bg_color = Color(0.25, 0.45, 0.75)
		
		var next_disabled = next_normal.duplicate()
		next_disabled.bg_color = Color(0.2, 0.3, 0.5)
		next_disabled.border_color = Color(0.25, 0.35, 0.6)
		
		next_button.add_theme_stylebox_override("normal", next_normal)
		next_button.add_theme_stylebox_override("hover", next_hover)
		next_button.add_theme_stylebox_override("pressed", next_pressed)
		next_button.add_theme_stylebox_override("disabled", next_disabled)
		next_button.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		next_button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.7))
	
	# Customize resize handle
	if window.has_node("ResizeHandle"):
		var resize_handle = window.get_node("ResizeHandle")
		resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
