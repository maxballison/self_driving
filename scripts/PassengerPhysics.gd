extends Node3D

@export var destination_id: int = 0
@export var passenger_name: String = "Passenger"

# Direction enum for compatibility with player
enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }

# State tracking
var is_picked_up: bool = false
var is_delivered: bool = false
var is_ragdolling: bool = false

# Visual nodes - will check existence
var visual_model = null
var destination_indicator = null
var ragdoll_body = null

# Car reference when picked up
var car_ref: Node3D = null

# Signals
# Signal is used but not connected directly, removing warning with slight rename
signal passenger_picked_up(passenger)
# Signal is used but not connected directly, removing warning with slight rename
signal passenger_delivered(passenger)
# Signal is used but not connected directly, removing warning with slight rename
signal passenger_hit_by_car(passenger)

func _ready():
	# Debug print for scene structure
	print("PassengerPhysics structure for ", name, ":")
	for child in get_children():
		print("- Child: ", child.name)
		
	# Find visual model (might have different name in your project)
	# Try different possible names
	visual_model = get_node_or_null("VisualModel")
	if not visual_model:
		# Look for any MeshInstance3D or Node3D children that might be the visual model
		for child in get_children():
			if (child is MeshInstance3D or child is Node3D) and "ragdoll" not in child.name.to_lower() and "destination" not in child.name.to_lower() and not child is RigidBody3D:
				visual_model = child
				print("Found alternative visual model: ", child.name)
				break
	
	# Find destination indicator
	destination_indicator = get_node_or_null("DestinationIndicator")
	if not destination_indicator:
		# Look for any MeshInstance3D children that might be the indicator
		for child in get_children():
			if child is MeshInstance3D and "destination" in child.name.to_lower():
				destination_indicator = child
				print("Found alternative destination indicator: ", child.name)
				break
	
	# Find ragdoll body
	ragdoll_body = get_node_or_null("RagdollBody")
	if not ragdoll_body:
		# Look for any RigidBody3D children that might be the ragdoll
		for child in get_children():
			if child is RigidBody3D:
				ragdoll_body = child
				print("Found alternative ragdoll body: ", child.name)
				break
	
	# Set color for destination indicator
	set_destination_color()
	
	# Make sure the rigid body starts in a clean state
	if ragdoll_body:
		print("Setting up ragdoll body: ", ragdoll_body.name)
		ragdoll_body.visible = false
		ragdoll_body.freeze = true
		
		# Ensure ragdoll has proper collision settings
		ragdoll_body.collision_layer = 2  # Layer 2
		ragdoll_body.collision_mask = 7   # Layers 1, 2, 3
		
		# Connect signal to monitor the ragdoll's collisions
		if not ragdoll_body.is_connected("body_entered", Callable(self, "_on_ragdoll_body_entered")):
			ragdoll_body.body_entered.connect(_on_ragdoll_body_entered)
	else:
		print("WARNING: No ragdoll body found for passenger: ", name)

func _process(_delta):
	# Update indicator position when picked up
	if is_picked_up and car_ref and destination_indicator:
		update_indicator_position()

func set_destination_color():
	# Set indicator color based on destination_id
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
	
	# Apply the color to the indicator if it exists
	if destination_indicator:
		# Create new material with emission
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.2
		
		destination_indicator.material_override = material

func pick_up(car: Node3D) -> bool:
	if is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Store reference to car
	car_ref = car
	is_picked_up = true
	
	# Hide the visual model if it exists
	if visual_model:
		visual_model.visible = false
	
	emit_signal("passenger_picked_up", self)
	return true

func deliver() -> bool:
	if not is_picked_up or is_delivered or is_ragdolling:
		return false
	
	is_picked_up = false
	is_delivered = true
	car_ref = null
	
	# Hide everything
	if visual_model:
		visual_model.visible = false
	
	if destination_indicator:
		destination_indicator.visible = false
	
	emit_signal("passenger_delivered", self)
	return true

# This is called when the car collides with the passenger
func activate_ragdoll(car = null, car_direction: int = -1):
	print("PASSENGER: Activating ragdoll physics! Car direction: ", car_direction)
	
	if is_ragdolling or is_picked_up or is_delivered:
		return
	
	is_ragdolling = true
	car_ref = car
	
	# Hide normal model and destination indicator
	if visual_model:
		visual_model.visible = false
	
	if destination_indicator:
		destination_indicator.visible = false
	
	# IMPORTANT: Make sure the ragdoll model is immediately displayed
	# and positioned correctly
	if ragdoll_body:
		print("Making ragdoll visible and unfreezing")
		ragdoll_body.visible = true
		
		# Calculate a force vector opposite to the car's movement direction
		# but with a significant upward component
		var impulse = Vector3(0, 5, 0)  # Default up
		
		if car_direction != -1:
			match car_direction:
				Direction.NORTH:  # Car coming from south, throw passenger north
					impulse = Vector3(0, 5, -15)
				Direction.SOUTH:  # Car coming from north, throw passenger south
					impulse = Vector3(0, 5, 15)
				Direction.EAST:   # Car coming from west, throw passenger east
					impulse = Vector3(15, 5, 0)
				Direction.WEST:   # Car coming from east, throw passenger west
					impulse = Vector3(-15, 5, 0)
		
		# Unfreeze physics immediately
		ragdoll_body.freeze = false
		if ragdoll_body.has_method("set_freeze_mode"):
			ragdoll_body.set_freeze_mode(RigidBody3D.FREEZE_MODE_KINEMATIC)
		
		# Apply forces immediately
		ragdoll_body.apply_central_impulse(impulse)
		
		# Add random torque for tumbling
		var random_torque = Vector3(
			randf_range(-1, 1),
			randf_range(-1, 1),
			randf_range(-1, 1)
		).normalized() * 15.0
		
		ragdoll_body.apply_torque(random_torque)
		
		# Make sure we emit the signal
		print("Passenger emitting hit_by_car signal")
		emit_signal("passenger_hit_by_car", self)
		
		# Ensure level gets reset (redundant but safe approach)
		var level_manager = get_node("/root/Main/LevelManager")
		if level_manager and level_manager.has_method("schedule_level_reset"):
			level_manager.schedule_level_reset(self)
	else:
		print("ERROR: No ragdoll body available for passenger: ", name)
		# Still try to reset the level even without ragdoll
		var level_manager = get_node("/root/Main/LevelManager")
		if level_manager and level_manager.has_method("schedule_level_reset"):
			level_manager.schedule_level_reset(self)

# In case the ragdoll collides with something
func _on_ragdoll_body_entered(body):
	print("Ragdoll collided with: ", body.name)
	# You can add additional collision responses here if needed

func update_indicator_position():
	if not is_picked_up or not car_ref or not destination_indicator:
		return
		
	# Check if we need to reparent the indicator
	if destination_indicator.get_parent() == self:
		# First appearance above car - maintain world position
		var global_pos = destination_indicator.global_position
		remove_child(destination_indicator)
		get_tree().root.add_child(destination_indicator)
		destination_indicator.global_position = global_pos
	
	# Stack indicators when multiple passengers are in car
	var car_passengers = car_ref.current_passengers
	var passenger_index = car_passengers.find(self)
	
	if passenger_index >= 0:
		# Position above car with spacing based on index
		destination_indicator.global_position = car_ref.global_position + Vector3(0, 1.0 + (passenger_index * 0.3), 0)
		
		
func reset_state() -> void:
	# Reset passenger to initial state
	if is_picked_up or is_delivered or is_ragdolling:
		print("Resetting passenger state: ", name)
		is_picked_up = false
		is_delivered = false
		is_ragdolling = false
		car_ref = null
		
		# Show the normal visual model
		if visual_model:
			visual_model.visible = true
		
		# Reset the ragdoll if it exists
		if ragdoll_body:
			ragdoll_body.visible = false
			ragdoll_body.freeze = true
		
		# Handle the destination indicator
		if destination_indicator:
			# If indicator was reparented to scene root, remove it
			if destination_indicator.get_parent() != self:
				destination_indicator.queue_free()
				
				# Create a new indicator
				var indicator_scene = destination_indicator.duplicate()
				add_child(indicator_scene)
				destination_indicator = indicator_scene
			
			# Make sure the indicator is visible and positioned correctly
			destination_indicator.visible = true
			destination_indicator.position = Vector3(0, 1.3, 0)
			
			# Set color again just to be safe
			set_destination_color()
