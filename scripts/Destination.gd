extends Node3D
class_name Destination

@export var destination_id: int = 0
@export var destination_name: String = "Destination"

# Visual elements
@onready var visual_model = $DestinationModel
@onready var flag = $DestinationModel/Flag
@onready var color_indicator = $ColorIndicator
@onready var animation_player = $AnimationPlayer
@onready var success_particles = $SuccessParticles
@onready var omni_light = $OmniLight3D

var is_completed: bool = false
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

signal passenger_delivered(destination_id)

func _ready() -> void:
	# Set the color based on the destination ID
	var color_index = destination_id % colors.size()
	var color = colors[color_index]
	
	# Apply color to flag
	if flag:
		# Create a new material for the flag
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
		material.flag_unshaded = false
		material.uv1_scale = Vector3(1.0, 1.0, 1.0)
		flag.material_override = material
	
	# Apply same color to light
	if omni_light:
		omni_light.light_color = color
	
	# Set up golden particles but don't emit yet
	if success_particles:
		setup_golden_particles()
		
		# Position the particles at the flag's position
		success_particles.global_position = flag.global_position
	
	# Start animation
	if animation_player:
		animation_player.play("flag_wave")

func setup_golden_particles() -> void:
	if not success_particles:
		return
	
	# Get the particle material
	var particle_material = success_particles.process_material
	if particle_material:
		# Set particle color to gold
		var gold_color = Color(1.0, 0.8, 0.2, 1.0)
		particle_material.color = gold_color
		
		# Set up glow material for the particles
		if success_particles.draw_pass_1:
			var material = StandardMaterial3D.new()
			material.albedo_color = gold_color
			material.emission_enabled = true
			material.emission = gold_color.lightened(0.3)
			material.emission_energy_multiplier = 3.0
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			success_particles.draw_pass_1.material = material

func complete_delivery() -> void:
	if is_completed:
		return
		
	is_completed = true
	
	# Make sure particles are at flag's position
	if success_particles and flag:
		success_particles.global_position = flag.global_position
	
	# Visual feedback for completed delivery
	if flag:
		# Brighten the flag briefly for a "success" visual
		var material = flag.material_override
		if material:
			var original_color = material.albedo_color
			var bright_color = original_color.lightened(0.5)
			
			# Create a tween for a brief flash effect
			var tween = create_tween()
			tween.tween_property(material, "emission_energy_multiplier", 3.0, 0.3)
			tween.tween_property(material, "emission_energy_multiplier", 0.6, 0.7)
			
			# After flash, dim the color
			tween.tween_callback(func():
				material.albedo_color = original_color.darkened(0.3)
				material.emission_energy_multiplier = 0.4
			)
	
	# Enhance light effect
	if omni_light:
		var tween = create_tween()
		tween.tween_property(omni_light, "light_energy", 3.0, 0.3)
		tween.tween_property(omni_light, "light_energy", 0.5, 0.7)
	
	# Play golden particle effect
	if success_particles:
		success_particles.emitting = true
		
		# Create a timer to stop particles after a while
		var timer = get_tree().create_timer(4.0)
		timer.timeout.connect(func(): success_particles.emitting = false)
	
	emit_signal("passenger_delivered", destination_id)
