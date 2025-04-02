extends Node3D

@export var destination_id: int = 0
@export var passenger_name: String = "Passenger"

# State tracking
var is_picked_up: bool = false
var is_delivered: bool = false
var is_ragdolling: bool = false

# Visual nodes
var visual_model = null
var destination_indicator = null
var ragdoll_body = null 

# Car reference when picked up
var car_ref: Node3D = null

# Signals
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger)
signal passenger_hit_by_car(passenger)

func _ready():
	# Add to passengers group for easy tracking
	add_to_group("passengers")
	
	# Find components
	for child in get_children():
		if (child is MeshInstance3D or child is Node3D) and "ragdoll" not in child.name.to_lower() and "destination" not in child.name.to_lower() and not child is RigidBody3D:
			visual_model = child
		
		if child is MeshInstance3D and "destination" in child.name.to_lower():
			destination_indicator = child
			
		if child is RigidBody3D:
			ragdoll_body = child
	
	# Initialize destination color
	set_destination_color()
	
	# Make sure the rigid body is properly configured for physics
	if ragdoll_body:
		ragdoll_body.visible = false
		ragdoll_body.freeze = true
		
		# Set collision layers
		ragdoll_body.collision_layer = 2  # Layer 2 (passengers)
		ragdoll_body.collision_mask = 7   # Layers 1, 2, 3 (environment, other passengers, car)
		
		# Connect collision signal
		if not ragdoll_body.is_connected("body_entered", Callable(self, "_on_ragdoll_body_entered")):
			ragdoll_body.body_entered.connect(_on_ragdoll_body_entered)
	else:
		print("WARNING: No ragdoll body found for passenger: ", name)

func _process(delta: float) -> void:
	# Update indicator position when picked up
	if is_picked_up and car_ref and destination_indicator:
		update_indicator_position()

# Helper function to identify this as a passenger in collision detection
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
	
	# Apply the color to the indicator
	if destination_indicator:
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
		
		destination_indicator.material_override = material

func pick_up(car: Node3D) -> bool:
	if is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Store car reference and update state
	car_ref = car
	is_picked_up = true
	
	# Hide visual model
	if visual_model:
		visual_model.visible = false
	
	emit_signal("passenger_picked_up", self)
	return true

func deliver() -> bool:
	if not is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Update state
	is_picked_up = false
	is_delivered = true
	car_ref = null
	
	# Hide visual elements
	if visual_model:
		visual_model.visible = false
	
	if destination_indicator:
		destination_indicator.visible = false
	
	emit_signal("passenger_delivered", self)
	return true

func activate_ragdoll(car = null, car_direction: int = -1) -> void:
	print("Activating passenger ragdoll physics for: ", name)
	
	if is_ragdolling or is_picked_up or is_delivered:
		print("Cannot activate ragdoll - passenger already in special state")
		return
	
	is_ragdolling = true
	car_ref = car
	
	# Find components if they haven't been assigned yet
	if visual_model == null:
		for child in get_children():
			if (child is MeshInstance3D or child is Node3D) and "ragdoll" not in child.name.to_lower() and "destination" not in child.name.to_lower() and not child is RigidBody3D:
				visual_model = child
				print("Found visual model: ", child.name)
			
	if destination_indicator == null:
		for child in get_children():
			if child is MeshInstance3D and "destination" in child.name.to_lower():
				destination_indicator = child
				print("Found destination indicator: ", child.name)
				
	if ragdoll_body == null:
		for child in get_children():
			if child is RigidBody3D:
				ragdoll_body = child
				print("Found ragdoll body: ", child.name)
				
	# Hide regular model (if found)
	if visual_model:
		print("Hiding visual model")
		visual_model.visible = false
	else:
		print("WARNING: No visual model found for passenger")
	
	if destination_indicator:
		print("Hiding destination indicator")
		destination_indicator.visible = false
	else:
		print("WARNING: No destination indicator found for passenger")
	
	# Activate ragdoll physics
	if ragdoll_body:
		print("Activating ragdoll physics body")
		ragdoll_body.visible = true
		
		# Ensure ragdoll has correct collision settings
		ragdoll_body.collision_layer = 2   # Layer 2 (passengers)
		ragdoll_body.collision_mask = 7    # Layers 1, 2, 3 (environment, passengers, car)
		
		# Calculate force direction - make stronger for more dramatic effect
		var impulse = Vector3(0, 10, 0)  # Increased upward force
		
		if car:
			# Calculate impulse based on car's position and direction
			var dir_to_car = global_position.direction_to(car.global_position)
			
			# If car_direction is -1, use physical relative positioning
			if car_direction == -1:
				# Apply force away from car direction with upward component
				impulse = -dir_to_car * 25.0 + Vector3(0, 10, 0)  # Increased force
			else:
				# Apply force based on car's discrete direction
				var dir_vec = Vector3.ZERO
				match car_direction:
					0: dir_vec = Vector3(0, 0, -1)  # North
					1: dir_vec = Vector3(1, 0, 0)   # East
					2: dir_vec = Vector3(0, 0, 1)   # South
					3: dir_vec = Vector3(-1, 0, 0)  # West
				
				impulse = dir_vec * 25.0 + Vector3(0, 10, 0)  # Increased force
		
		# Make sure ragdoll is at the passenger's position
		ragdoll_body.global_position = global_position
		
		# Unfreeze physics and apply forces
		ragdoll_body.freeze = false
		ragdoll_body.apply_central_impulse(impulse)
		
		# Add more random torque for more dramatic tumbling
		var random_torque = Vector3(
			randf_range(-3, 3),  # Increased range
			randf_range(-3, 3),
			randf_range(-3, 3)
		).normalized() * 30.0  # Increased torque
		
		ragdoll_body.apply_torque(random_torque)
		
		# Signal the collision
		emit_signal("passenger_hit_by_car", self)
		
		# DON'T immediately schedule level reset - let physics simulation play out
		# Instead, let the Player.gd handle this with a proper delay
	else:
		print("ERROR: No ragdoll body available for passenger: ", name)
		
		# Still try to reset the level even without ragdoll
		var level_manager = get_node("/root/Main/LevelManager")
		if level_manager and level_manager.has_method("schedule_level_reset"):
			level_manager.schedule_level_reset(self)

func _on_ragdoll_body_entered(body) -> void:
	print("Ragdoll collided with: ", body.name)
	
	# Check if this is a secondary collision with the environment
	if body is StaticBody3D and "floor" not in body.name.to_lower():
		# Additional effects for wall collisions could be added here
		pass

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
		if visual_model:
			visual_model.visible = true
		
		# Reset ragdoll
		if ragdoll_body:
			ragdoll_body.visible = false
			ragdoll_body.freeze = true
			# Reset physics state
			ragdoll_body.linear_velocity = Vector3.ZERO
			ragdoll_body.angular_velocity = Vector3.ZERO
			ragdoll_body.position = Vector3.ZERO
		
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
			destination_indicator.position = Vector3(0, 1.3, 0)
			
			# Reset color
			set_destination_color()
