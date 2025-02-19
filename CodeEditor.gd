# CodeEditor.gd
extends Control

@onready var text_edit = $TextEdit
@onready var run_button = $RunButton
# Look up the interpreter in the scene tree (adjust the path if needed)
@onready var interpreter = get_node("/root/Main/ScriptInterpreter")

func _ready() -> void:
	run_button.pressed.connect(_on_RunButton_pressed)
	# Enable the window to capture mouse events for dragging.
	self.mouse_filter = Control.MOUSE_FILTER_STOP

# --- Drag-to-move code editor window ---
var dragging = false
var drag_offset = Vector2()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_offset = self.get_global_mouse_position() - self.position
			else:
				dragging = false
	elif event is InputEventMouseMotion and dragging:
		self.position = self.get_global_mouse_position() - drag_offset

# --- Run button callback: pass the code to the interpreter ---
func _on_RunButton_pressed() -> void:
	var code = text_edit.text
	interpreter.execute_script(code)
