extends Node3D
class_name Destination

@export var destination_id: int = 0
@export var destination_name: String = "Destination"

# Visual elements
@onready var visual_model = $DestinationModel
@onready var color_indicator = $ColorIndicator

var is_completed: bool = false

signal passenger_delivered(destination_id)

func _ready() -> void:
	# Set the color based on the destination ID
	var colors = [
		Color(1, 0, 0),    # Red
		Color(0, 1, 0),    # Green 
		Color(0, 0, 1),    # Blue
		Color(1, 1, 0),    # Yellow
		Color(1, 0, 1),    # Magenta
		Color(0, 1, 1),    # Cyan
		Color(1, 0.5, 0),  # Orange
		Color(0.5, 0, 1)   # Purple
	]
	
	var color_index = destination_id % colors.size()
	var color = colors[color_index]
	
	if color_indicator:
		# Create a new material
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
		color_indicator.material_override = material

func complete_delivery() -> void:
	if is_completed:
		return
		
	is_completed = true
	
	# Visual feedback for completed delivery
	if color_indicator:
		# Show checkmark or change appearance
		var material = color_indicator.material_override
		if material:
			# Dim the color to indicate completion
			material.albedo_color = material.albedo_color.darkened(0.5)
			material.emission_energy_multiplier = 0.4
	
	emit_signal("passenger_delivered", destination_id)
