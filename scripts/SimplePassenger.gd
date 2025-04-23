extends RigidBody3D

@export var destination_id: int = 0
@export var passenger_name: String = "Passenger"

# State tracking
var is_picked_up: bool = false
var is_delivered: bool = false
var is_ragdolling: bool = false

# Car reference when picked up
var car_ref: Node3D = null

var is_in_pickup_range = false
var outline_effect = null
var particle_effect = null
var pulse_animation = null

# Cached references for better performance
@onready var passenger_model = $PassengerModel
@onready var destination_indicator = $DestinationIndicator

# Signals
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger)
signal passenger_hit_by_car(passenger)

func _ready():
	# Add to passengers group for easy tracking
	add_to_group("passengers")
	
	# Initialize destination color
	set_destination_color()
	if destination_indicator:
		destination_indicator.visible = false
	
	# Initialize frozen state
	freeze = true
	
	# Set up collision properties
	collision_layer = 2  # Layer 2 (passengers)
	collision_mask = 7   # Layer 1+2+3 (environment, other passengers, player)
	
	# Make sure we can detect collisions with the player
	contact_monitor = true
	max_contacts_reported = 3
	
	# Clear signals and connect our own
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		body_entered.connect(_on_body_entered)
	
	print("SimplePassenger initialized: ", name, " with destination ID: ", destination_id)
	setup_pickup_highlight_effect()

func _process(delta: float) -> void:
	# Update indicator position when picked up
	if is_picked_up and car_ref and destination_indicator:
		update_indicator_position()
		
		
func setup_pickup_highlight_effect():
	# Create a container for all visual effects
	outline_effect = Node3D.new()
	outline_effect.name = "PickupHighlightEffect"
	add_child(outline_effect)
	

	var pickup_icon = MeshInstance3D.new()
	pickup_icon.name = "PickupIcon"
	
	# Create a small plane mesh for the icon
	var icon_mesh = QuadMesh.new()
	icon_mesh.size = Vector2(0.3, 0.3)
	pickup_icon.mesh = icon_mesh
	
	# Create a material with an arrow texture or icon
	var icon_material = StandardMaterial3D.new()
	icon_material.albedo_color = Color(1, 1, 1, 0.9)
	icon_material.emission_enabled = true
	icon_material.emission = Color(1, 1, 0, 1)
	icon_material.emission_energy_multiplier = 1.5
	icon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	icon_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	
	pickup_icon.material_override = icon_material
	pickup_icon.position = Vector3(0, 1.5, 0)
	outline_effect.add_child(pickup_icon)
	
	# Create pulsing animation
	pulse_animation = AnimationPlayer.new()
	outline_effect.add_child(pulse_animation)
	
	var animation = Animation.new()
	var track_index = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, "../GlowingOutline:material_override:emission_energy_multiplier")
	animation.track_insert_key(track_index, 0.0, 1.5)
	animation.track_insert_key(track_index, 0.5, 3.0)
	animation.track_insert_key(track_index, 1.0, 1.5)
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR
	
	var animation_lib = AnimationLibrary.new()
	animation_lib.add_animation("pulse", animation)
	pulse_animation.add_animation_library("", animation_lib)
	
	# Hide effect initially
	outline_effect.visible = false
	
# Call this when passenger enters pickup range
func set_pickup_highlight(enabled: bool):
	if outline_effect == null:
		return
		
	is_in_pickup_range = enabled
	
	# Don't show highlight if passenger is already picked up or delivered
	if is_picked_up or is_delivered or is_ragdolling:
		outline_effect.visible = false
		return
		
	outline_effect.visible = enabled
	
	if enabled:
		# Start the animation and particles
		pulse_animation.play("pulse")
			
		# Add a subtle floating motion to the icon
		var tween = create_tween().set_loops()
		tween.tween_property(outline_effect.get_node("PickupIcon"), "position:y", 
							 1.6, 1.0).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(outline_effect.get_node("PickupIcon"), "position:y", 
							 1.4, 1.0).set_ease(Tween.EASE_IN_OUT)
	else:
		# Stop the animation and particles
		pulse_animation.stop()

# Helper functions for improved detection
func is_passenger() -> bool:
	return true


func set_destination_color() -> void:
	# Define standard colors for destinations
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
	
	# Create a material for the indicator
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = false
	material.emission = color
	material.emission_energy_multiplier = 1.2
	
	# Apply the color to the indicator
	if destination_indicator:
		destination_indicator.material_override = material
	
	# Apply the same color to the body part of the passenger model
	if passenger_model:
		# Create a duplicate of the material for the passenger body
		var body_material = material.duplicate()
		
		# Find the body/shirt mesh using a recursive helper function
		_apply_material_to_body_parts(passenger_model, body_material)
		
# Helper function to recursively find and color body parts
func _apply_material_to_body_parts(node: Node, material: Material) -> void:
	# Check each child of the current node
	for child in node.get_children():
		# If the child is a MeshInstance3D and has a name that suggests it's a body part
		if child is MeshInstance3D:
			var name_lower = child.name.to_lower()
			# Apply material only to body/torso/shirt parts
			if "body" in name_lower or "leftarm" in name_lower or "rightarm" in name_lower:
				child.material_override = material
		
		# Recursively check children of this node
		_apply_material_to_body_parts(child, material)

func pick_up(car: Node3D) -> bool:
	if is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Store car reference and update state
	car_ref = car
	is_picked_up = true
	
	# Hide visual model, freeze physics
	if passenger_model:
		passenger_model.visible = false
	if destination_indicator:
		destination_indicator.visible = true
	
	# Disable collision while picked up
	collision_layer = 0
	collision_mask = 0
	
	emit_signal("passenger_picked_up", self)
	set_pickup_highlight(false)
	return true

func deliver() -> bool:
	if not is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Update state
	is_picked_up = false
	is_delivered = true
	car_ref = null
	
	# Hide visual elements
	if passenger_model:
		passenger_model.visible = false
	
	if destination_indicator:
		destination_indicator.visible = false
	
	emit_signal("passenger_delivered", self)
	return true

func activate_ragdoll(car = null, car_direction: int = -1) -> void:
	print("Activating SimplePassenger ragdoll physics for: ", name)
	
	if is_ragdolling or is_picked_up or is_delivered:
		print("Cannot activate ragdoll - passenger already in special state")
		return
	
	is_ragdolling = true
	car_ref = car
	
	# IMPORTANT FIX: Don't hide the model when ragdolling! The SimplePassenger is the ragdoll.
	# We should keep the model visible and just apply physics.
	
	# Enable physics by unfreezing and setting appropriate collision settings
	print("Enabling physics for ragdoll effect")
	freeze = false
	collision_layer = 2   # Layer 2 (passengers)
	collision_mask = 7    # Layers 1+2+3 (environment, other passengers, player)
	
	# Hide only the destination indicator, keep passenger visible
	if destination_indicator:
		print("Hiding destination indicator")
		destination_indicator.visible = false
	
	# Make sure passenger model remains visible and correctly positioned
	if passenger_model:
		passenger_model.visible = true
		print("Ensuring passenger model is visible for ragdoll")
		
	if outline_effect:
		outline_effect.visible = false
		
	# Make sure we're visible at the node level too
	visible = true
	
	# Calculate force direction - make even stronger for more dramatic effect
	var impulse = Vector3(0, 15, 0)  # Strong upward force
	
	if car:
		# Calculate impulse based on car's position and direction
		var dir_to_car = global_position.direction_to(car.global_position)
		
		# If car_direction is -1, use physical relative positioning
		if car_direction == -1:
			# Apply force away from car direction with upward component
			print("Applying force away from car direction")
			impulse = -dir_to_car * 40.0 + Vector3(0, 20, 0)  # Stronger force
		else:
			# Apply force based on car's discrete direction
			var dir_vec = Vector3.ZERO
			match car_direction:
				0: dir_vec = Vector3(0, 0, -1)  # North
				1: dir_vec = Vector3(1, 0, 0)   # East
				2: dir_vec = Vector3(0, 0, 1)   # South
				3: dir_vec = Vector3(-1, 0, 0)  # West
			
			print("Applying force based on car direction: ", car_direction)
			impulse = dir_vec * 40.0 + Vector3(0, 20, 0)  # Stronger force
	
	# Apply forces - even stronger for more dramatic effect
	print("Applying impulse: ", impulse)
	apply_central_impulse(impulse)
	
	# Ensure we're unfrozen and visible
	freeze = false
	visible = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	
	# Add random torque for more dramatic tumbling
	var random_torque = Vector3(
		randf_range(-5, 5),  # Increased range
		randf_range(-5, 5),
		randf_range(-5, 5)
	).normalized() * 50.0  # Stronger torque
	
	print("Applying torque: ", random_torque)
	apply_torque(random_torque)
	
	# Signal the collision
	emit_signal("passenger_hit_by_car", self)
	print("Emitted passenger_hit_by_car signal")
	
	# Play sound effect if available
	var main = get_node_or_null("/root/Main")
	if main and main.has_method("play_sound"):
		main.play_sound("crash", -5, 0.9 + randf() * 0.2)
		
	# Create a visual effect to draw attention to the collision
	if main and main.has_method("spawn_particles"):
		main.spawn_particles(global_position, Color(1.0, 0.2, 0.2), 30)
		print("Spawned collision particles")
	
	# Manually schedule level reset after a delay
	var level_manager = get_node_or_null("/root/Main/LevelManager")
	if level_manager and level_manager.has_method("schedule_level_reset"):
		print("Scheduling level reset from SimplePassenger")
		level_manager.schedule_level_reset(self)

func _on_body_entered(body) -> void:
	# Check if this is a collision with the player
	if not is_ragdolling and not is_picked_up and not is_delivered:
		print("Passenger detected collision with: ", body.name)
		
		# Try to detect the player using multiple methods
		var is_player = false
		var player_ref = null
		
		# Direct detection - this is the player body itself
		if body.name == "Player" or (body.get_parent() and body.get_parent().name == "Player"):
			is_player = true
			player_ref = body if body.name == "Player" else body.get_parent()
			print("Player collision confirmed with: ", player_ref.name)
		
		# Function-based detection
		elif body.has_method("drive") or (body.get_parent() and body.get_parent().has_method("drive")):
			is_player = true
			player_ref = body if body.has_method("drive") else body.get_parent()
			print("Player detected via drive method: ", player_ref.name)
		
		# If we found the player, activate ragdoll
		if is_player and player_ref:
			print("Passenger hit by player car - activating ragdoll: ", name)
			
			# Call the player's passenger_hit method if available
			if player_ref.has_method("emit_signal"):
				player_ref.emit_signal("passenger_hit", self)
			
			# Activate the ragdoll physics
			activate_ragdoll(player_ref, -1)
			
			# Schedule a level reset via the level manager
			var level_manager = get_node_or_null("/root/Main/LevelManager")
			if level_manager and level_manager.has_method("schedule_level_reset"):
				level_manager.schedule_level_reset(self)

func update_indicator_position() -> void:
	if not is_picked_up or not car_ref or not destination_indicator:
		return
		
	# First time pickup: reparent the indicator to the scene root
	if destination_indicator.get_parent() == self:
		var global_pos = destination_indicator.global_position
		remove_child(destination_indicator)
		get_tree().root.add_child(destination_indicator)
		destination_indicator.global_position = global_pos
	
	# Position indicator above car, stacked if multiple passengers
	var car_passengers = car_ref.current_passengers
	var passenger_index = car_passengers.find(self)
	
	if passenger_index >= 0:
		destination_indicator.global_position = car_ref.global_position + Vector3(0, 1.0 + (passenger_index * 0.3), 0)

func reset_state() -> void:
	# Reset to initial state
	if is_picked_up or is_delivered or is_ragdolling:
		print("Resetting passenger state: ", name)
		is_picked_up = false
		is_delivered = false
		is_ragdolling = false
		car_ref = null
		
		# Show visual model
		if passenger_model:
			passenger_model.visible = true
		
		# Reset physics state
		freeze = true
		collision_layer = 2
		collision_mask = 7
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		
		# Reset position
		rotation = Vector3.ZERO
		
		# Reset indicator
		if destination_indicator:
			# If indicator was reparented to scene root, remove it
			if destination_indicator.get_parent() != self:
				destination_indicator.queue_free()
				
				# Create a new indicator
				var indicator_scene = destination_indicator.duplicate()
				add_child(indicator_scene)
				destination_indicator = indicator_scene
			
			# Make sure indicator is visible and positioned correctly
			destination_indicator.visible = true
			destination_indicator.position = Vector3(0, 1.64773, 0)
			
			# Reset color
			set_destination_color()
