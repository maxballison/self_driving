extends Resource
class_name TutorialTheme

# Apply theme to the tutorial window, inheriting from CodeEditorTheme styling
static func apply_theme(window: Control) -> void:
	# Reuse the base theme from CodeEditorTheme
	window.theme = CodeEditorTheme.create_theme()
	
	# Set up fonts - use a regular font for UI text and monospace only for code
	var regular_font = SystemFont.new()
	regular_font.font_names = ["Open Sans", "Noto Sans", "Arial", "Helvetica"]
	regular_font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	
	var mono_font = SystemFont.new()
	mono_font.font_names = ["JetBrains Mono", "Consolas", "DejaVu Sans Mono"]
	mono_font.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	
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
		
		# Apply font to title
		if window.has_node("TitleBar/TitleLabel"):
			var title_label = window.get_node("TitleBar/TitleLabel")
			title_label.add_theme_font_override("font", regular_font)
			title_label.add_theme_font_size_override("font_size", 25)
	
	# Style the tab container
	if window.has_node("TabContainer"):
		var tabs = window.get_node("TabContainer")
		
		# Tab font
		tabs.add_theme_font_override("font", regular_font)
		tabs.add_theme_font_size_override("font_size", 20)
		
		# Tab style
		var tab_bg = StyleBoxFlat.new()
		tab_bg.bg_color = Color(0.15, 0.15, 0.18)
		tab_bg.border_width_left = 1
		tab_bg.border_width_top = 1
		tab_bg.border_width_right = 1
		tab_bg.border_color = Color(0.28, 0.28, 0.33)
		tab_bg.corner_radius_top_left = 3
		tab_bg.corner_radius_top_right = 3
		tabs.add_theme_stylebox_override("tab_unselected", tab_bg)
		
		var tab_selected = tab_bg.duplicate()
		tab_selected.bg_color = Color(0.18, 0.18, 0.22)
		tab_selected.border_color = Color(0.35, 0.35, 0.4)
		tabs.add_theme_stylebox_override("tab_selected", tab_selected)
		
		var panel_bg = StyleBoxFlat.new()
		panel_bg.bg_color = Color(0.13, 0.13, 0.16)
		panel_bg.border_width_left = 1
		panel_bg.border_width_right = 1
		panel_bg.border_width_bottom = 1
		panel_bg.border_color = Color(0.28, 0.28, 0.33)
		tabs.add_theme_stylebox_override("panel", panel_bg)
	
	# Style for message container in tutorial tab
	if window.has_node("TabContainer/TutorialTab/MessageContainer"):
		var message_container = window.get_node("TabContainer/TutorialTab/MessageContainer")
		var message_bg = StyleBoxFlat.new()
		message_bg.bg_color = Color(0.12, 0.12, 0.15)  # Dark background
		message_bg.border_width_left = 1
		message_bg.border_width_top = 1
		message_bg.border_width_right = 1
		message_bg.border_width_bottom = 1
		message_bg.border_color = Color(0.25, 0.25, 0.3)
		message_container.add_theme_stylebox_override("panel", message_bg)
	
	# Style all RichTextLabels in the tutorial using the regular font
	var rtl_nodes = [
		"TabContainer/TutorialTab/MessageContainer/RichTextLabel",
		"TabContainer/DocsTab/HSplitContainer/FunctionDescription/RichTextLabel"
	]
	
	for path in rtl_nodes:
		if window.has_node(path):
			var rtl = window.get_node(path)
			
			# Regular font for normal text
			rtl.add_theme_font_override("normal_font", regular_font)
			rtl.add_theme_font_size_override("normal_font_size", 22)
			rtl.add_theme_font_override("bold_font", regular_font)
			rtl.add_theme_font_size_override("bold_font_size", 22)
			
			# Monospace font for code blocks only
			rtl.add_theme_font_override("mono_font", mono_font)
			rtl.add_theme_font_size_override("mono_font_size", 20)
			
			# Set text colors
			rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
			rtl.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0))
			rtl.add_theme_color_override("selection_color", Color(0.3, 0.4, 0.6, 0.5))
			
			# Style code blocks
			var code_bg = StyleBoxFlat.new()
			code_bg.bg_color = Color(0.1, 0.1, 0.12)
			code_bg.border_width_left = 2
			code_bg.border_color = Color(0.4, 0.6, 0.9, 0.5)
			code_bg.expand_margin_left = 8.0
			code_bg.corner_radius_top_left = 3
			code_bg.corner_radius_bottom_left = 3
			rtl.add_theme_stylebox_override("code_normal", code_bg)
			
			# Add padding
			rtl.add_theme_constant_override("line_separation", 6)
			rtl.add_theme_constant_override("table_h_separation", 10)
			rtl.add_theme_constant_override("table_v_separation", 6)
	
	# Style the function list in docs tab
	if window.has_node("TabContainer/DocsTab/HSplitContainer/FunctionList"):
		var function_list = window.get_node("TabContainer/DocsTab/HSplitContainer/FunctionList")
		
		# Font
		function_list.add_theme_font_override("font", regular_font)
		function_list.add_theme_font_size_override("font_size", 20)
		
		# Item styles
		var item_normal = StyleBoxFlat.new()
		item_normal.bg_color = Color(0.15, 0.15, 0.18)
		function_list.add_theme_stylebox_override("panel", item_normal)
		
		var item_selected = StyleBoxFlat.new()
		item_selected.bg_color = Color(0.3, 0.5, 0.8, 0.3)
		function_list.add_theme_stylebox_override("selected", item_selected)
		
		var item_hovered = StyleBoxFlat.new()
		item_hovered.bg_color = Color(0.2, 0.2, 0.24)
		function_list.add_theme_stylebox_override("hovered", item_hovered)
		
		# Text colors
		function_list.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		function_list.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0))
	
	# Style for button panel
	if window.has_node("ButtonPanel"):
		var button_panel = window.get_node("ButtonPanel") 
		var button_panel_style = StyleBoxFlat.new()
		button_panel_style.bg_color = Color(0.17, 0.17, 0.2)
		button_panel_style.border_width_top = 1
		button_panel_style.border_color = Color(0.25, 0.25, 0.3)
		button_panel.add_theme_stylebox_override("panel", button_panel_style)
	
	# Create button styles - we'll reuse these for both buttons
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.3, 0.5, 0.8)  # Blue button
	btn_normal.border_width_left = 1
	btn_normal.border_width_top = 1
	btn_normal.border_width_right = 1
	btn_normal.border_width_bottom = 1
	btn_normal.border_color = Color(0.4, 0.6, 0.9)
	btn_normal.corner_radius_top_left = 3
	btn_normal.corner_radius_top_right = 3
	btn_normal.corner_radius_bottom_right = 3
	btn_normal.corner_radius_bottom_left = 3
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.35, 0.55, 0.85)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.25, 0.45, 0.75)
	
	var btn_disabled = btn_normal.duplicate()
	btn_disabled.bg_color = Color(0.2, 0.3, 0.5)
	btn_disabled.border_color = Color(0.25, 0.35, 0.6)
	
	# Style for Next button
	if window.has_node("ButtonPanel/NextButton"):
		var next_button = window.get_node("ButtonPanel/NextButton")
		
		next_button.add_theme_font_override("font", regular_font)
		next_button.add_theme_font_size_override("font_size", 20)
		
		next_button.add_theme_stylebox_override("normal", btn_normal)
		next_button.add_theme_stylebox_override("hover", btn_hover)
		next_button.add_theme_stylebox_override("pressed", btn_pressed)
		next_button.add_theme_stylebox_override("disabled", btn_disabled)
		next_button.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		next_button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.7))
	
	# Style for Back button - use the same style as Next button but with a different color
	if window.has_node("ButtonPanel/BackButton"):
		var back_button = window.get_node("ButtonPanel/BackButton")
		
		back_button.add_theme_font_override("font", regular_font)
		back_button.add_theme_font_size_override("font_size", 20)
		
		var back_normal = btn_normal.duplicate()
		back_normal.bg_color = Color(0.4, 0.4, 0.5)  # Gray button
		back_normal.border_color = Color(0.5, 0.5, 0.6)
		
		var back_hover = back_normal.duplicate() 
		back_hover.bg_color = Color(0.45, 0.45, 0.55)
		
		var back_pressed = back_normal.duplicate()
		back_pressed.bg_color = Color(0.35, 0.35, 0.45)
		
		var back_disabled = back_normal.duplicate()
		back_disabled.bg_color = Color(0.3, 0.3, 0.4) 
		back_disabled.border_color = Color(0.35, 0.35, 0.45)
		
		back_button.add_theme_stylebox_override("normal", back_normal)
		back_button.add_theme_stylebox_override("hover", back_hover)
		back_button.add_theme_stylebox_override("pressed", back_pressed)
		back_button.add_theme_stylebox_override("disabled", back_disabled)
		back_button.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		back_button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.7))
	
	# Customize resize handle
	if window.has_node("ResizeHandle"):
		var resize_handle = window.get_node("ResizeHandle")
		resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
