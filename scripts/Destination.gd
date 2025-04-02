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
@onready var delivery_area = $DeliveryArea

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

signal destination_passenger_delivered(destination_id)

func _ready() -> void:
	# Add to destinations group for tracking
	add_to_group("destinations")
	
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
	
	# Configure delivery area for proper physics detection
	if delivery_area:
		# Set collision mask to detect the player's pickup area (Layer 4)
		delivery_area.collision_layer = 8   # Layer 4 - destination areas
		delivery_area.collision_mask = 4    # Layer 3 - player/car
		
		# Connect delivery area signals for physics-based detection
		if not delivery_area.is_connected("body_entered", Callable(self, "_on_delivery_area_body_entered")):
			delivery_area.connect("body_entered", Callable(self, "_on_delivery_area_body_entered"))
		
		if not delivery_area.is_connected("body_exited", Callable(self, "_on_delivery_area_body_exited")):
			delivery_area.connect("body_exited", Callable(self, "_on_delivery_area_body_exited"))

# Helper function for identifying destination in collision detection
func is_destination() -> bool:
	return true

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

func _on_delivery_area_body_entered(body: Node) -> void:
	# Detect when a car enters the delivery area
	print("Delivery area detected body: ", body.name)
	
	# More robust detection for the player car
	var car = null
	if body is RigidBody3D and body.name == "Player":
		# Direct body is the player car
		car = body
		print("Direct player car detected!")
	elif body is Node3D and body.get_parent() and body.get_parent().has_method("drive"):
		# Parent has drive method (traditional detection)
		car = body.get_parent()
		print("Parent car detected via drive method")
	
	# Add this destination to the car's nearby destinations
	if car != null:
		if car.has_method("_on_pickup_area_body_entered"):
			# Pass this node as parent to the car
			print("Adding destination to car's nearby destinations")
			car._on_pickup_area_body_entered(self)
		elif "nearby_destinations" in car:
			# Direct property access as fallback
			print("Direct property access for destinations")
			if not car.nearby_destinations.has(self):
				car.nearby_destinations.append(self)

func _on_delivery_area_body_exited(body: Node) -> void:
	# Detect when a car leaves the delivery area
	print("Body exited delivery area: ", body.name)
	
	# More robust detection for the player car
	var car = null
	if body is RigidBody3D and body.name == "Player":
		# Direct body is the player car
		car = body
		print("Player car exited")
	elif body is Node3D and body.get_parent() and body.get_parent().has_method("drive"):
		# Parent has drive method (traditional detection)
		car = body.get_parent()
		print("Parent car exited")
	
	# Remove this destination from the car's nearby destinations
	if car != null:
		if car.has_method("_on_pickup_area_body_exited"):
			# Use method if available
			print("Removing destination using method")
			car._on_pickup_area_body_exited(self)
		elif "nearby_destinations" in car:
			# Direct property access as fallback
			print("Removing destination using direct property access")
			var idx = car.nearby_destinations.find(self)
			if idx != -1:
				car.nearby_destinations.remove_at(idx)

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
	
	emit_signal("destination_passenger_delivered", destination_id)
