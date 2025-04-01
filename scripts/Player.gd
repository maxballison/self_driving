extends RigidBody3D

# Movement variables
var is_driving: bool = false
var move_speed: float = 25.0  # Speed for movement
var max_velocity: float = 10.0  # Maximum velocity to prevent excessive speed
var turn_in_progress: bool = false
var turn_direction: int = 0 # 1 for left, -1 for right
var turn_queued: bool = false
var can_reset: bool = true
var is_grounded: bool = false # Track if car is on the ground

# Direction vector (normalized)
var current_direction: Vector3 = Vector3(0, 0, -1)  # Forward direction

# Fall detection
var fall_threshold: float = -10.0  # Y position below which the car is considered fallen
var reset_in_progress: bool = false  # Track if a reset is already happening

# Passenger tracking
var current_passengers: Array = []
var max_passengers: int = 3
var nearby_passengers: Array = []
var nearby_destinations: Array = []

# References to components
@onready var pickup_area = $PassengerPickupArea
@onready var car_model = $CarModel
@onready var reset_protection_timer = $ResetProtectionTimer

# Signals
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)
signal passenger_hit(passenger)
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger, destination)
signal level_completed()

func _ready() -> void:
	# Set initial direction based on rotation
	update_direction_from_rotation()
	
	# Initialize physics
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	
	# Connect pickup area signals
	if pickup_area:
		pickup_area.collision_mask = 2  # Layer 2 (passengers)
		
		if not pickup_area.is_connected("body_entered", Callable(self, "_on_pickup_area_body_entered")):
			pickup_area.connect("body_entered", Callable(self, "_on_pickup_area_body_entered"))
		
		if not pickup_area.is_connected("body_exited", Callable(self, "_on_pickup_area_body_exited")):
			pickup_area.connect("body_exited", Callable(self, "_on_pickup_area_body_exited"))
	
	# Connect reset protection timer
	if not reset_protection_timer.is_connected("timeout", Callable(self, "_on_reset_protection_timeout")):
		reset_protection_timer.timeout.connect(_on_reset_protection_timeout)
	
	# Make sure reset flags are cleared
	reset_in_progress = false
	can_reset = true
	
	clear_passengers()

func _physics_process(delta: float) -> void:
	# Check if car is grounded
	is_grounded = _check_grounded()
	
	# Only restrict rotation if we're on the ground
	if is_grounded:
		# Keep the car upright on ground (no rolling)
		var current_rot = rotation
		rotation = Vector3(0, current_rot.y, 0)
		
		# Prevent flipping by zeroing out x and z angular velocity
		angular_velocity.x = 0
		angular_velocity.z = 0
	
	# Apply continuous driving force if needed (only when grounded)
	if is_driving and not turn_in_progress and is_grounded:
		# Calculate current forward velocity
		var forward_velocity = current_direction.dot(linear_velocity)
		
		# Only apply force if below max speed
		if forward_velocity < max_velocity:
			# Apply less force as we approach max speed
			var speed_factor = clamp(1.0 - (forward_velocity / max_velocity), 0.1, 1.0)
			apply_central_force(current_direction * move_speed * 40.0 * speed_factor)
	
	# Process turn queue if needed
	if turn_queued and not turn_in_progress:
		turn_queued = false
		_perform_turn()
	
	# Check for falling below threshold (with additional protection against multiple resets)
	if position.y < fall_threshold and can_reset and not reset_in_progress:
		_handle_fall()

# Ground check using raycasts
func _check_grounded() -> bool:
	# Cast a ray downward to check for ground
	var ray_length = 0.4 # Adjust based on car height
	var space_state = get_world_3d().direct_space_state
	
	# Create a query for the raycast
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -ray_length, 0),
		1, # Collision mask (Layer 1)
		[get_rid()] # Exclude self
	)
	
	var result = space_state.intersect_ray(query)
	return not result.is_empty()

func update_direction_from_rotation() -> void:
	# Calculate direction vector from rotation
	current_direction = Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y).normalized()
	print("Direction updated: ", current_direction)

# Actually perform the turn
func _perform_turn() -> void:
	if turn_in_progress:
		return
	
	turn_in_progress = true
	
	# Store current driving state
	var was_driving = is_driving
	is_driving = false
	
	# Apply braking force for stability
	var brake_force = -linear_velocity * 8.0
	apply_central_force(brake_force)
	
	# Rotate based on direction
	rotation.y += PI/2 * turn_direction
	update_direction_from_rotation()
	
	# Apply impulse in new direction if grounded
	if is_grounded:
		apply_central_impulse(current_direction * move_speed * 0.3)
	
	# Schedule turn completion
	var timer = get_tree().create_timer(0.1)
	await timer.timeout
	
	# Turn is done
	turn_in_progress = false
	is_driving = was_driving
	
	print("Turn completed")

# COMMAND FUNCTIONS

func drive() -> void:
	is_driving = true
	
	# Only apply impulse if grounded
	if is_grounded:
		# Apply initial impulse to get moving immediately
		apply_central_impulse(current_direction * move_speed * 0.5)
	
	print("Car started driving continuously")

func stop() -> void:
	if not is_driving:
		return
		
	is_driving = false
	
	# Apply braking force
	var brake_force = -linear_velocity.normalized() * linear_velocity.length() * 10.0
	apply_central_force(brake_force)
	print("Car stopped")

func turn_left() -> void:
	# Queue a left turn
	turn_direction = 1
	turn_queued = true
	print("Turn left queued")

func turn_right() -> void:
	# Queue a right turn
	turn_direction = -1
	turn_queued = true
	print("Turn right queued")

func wait(seconds: float) -> void:
	# Store current driving state
	var was_driving = is_driving
	is_driving = false
	
	print("Waiting for ", seconds, " seconds")
	await get_tree().create_timer(seconds).timeout
	
	# Resume previous state
	is_driving = was_driving
	print("Wait complete, driving state: ", is_driving)

func pick_up() -> bool:
	if current_passengers.size() >= max_passengers:
		print("Car is full! Cannot pick up more passengers.")
		return false
	
	# Try to pick up nearby passengers
	if nearby_passengers.size() > 0:
		for passenger in nearby_passengers:
			if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
				if passenger.pick_up(self):
					current_passengers.append(passenger)
					print("Picked up passenger going to destination ", passenger.destination_id)
					emit_signal("passenger_picked_up", passenger)
					return true
	
	print("No passengers to pick up nearby!")
	return false

func drop_off() -> bool:
	if current_passengers.size() == 0:
		print("No passengers in car to drop off!")
		return false
	
	# Check for nearby destinations
	if nearby_destinations.size() > 0:
		for destination in nearby_destinations:
			# Find a passenger that matches this destination
			for i in range(current_passengers.size()):
				var passenger = current_passengers[i]
				if passenger.destination_id == destination.destination_id:
					if passenger.deliver():
						# Remove from current passengers array
						current_passengers.remove_at(i)
						
						destination.complete_delivery()
						print("Dropped off passenger at destination ", passenger.destination_id)
						emit_signal("passenger_delivered", passenger, destination)
						
						# Check if all passengers have been delivered
						check_level_completion()
						return true
	
	print("No matching destination nearby for any passenger!")
	return false

# COLLISION HANDLING

func _on_pickup_area_body_entered(body: Node) -> void:
	print("Body entered pickup area: ", body.name)
	
	# Check if the body is a passenger's ragdoll
	if body is RigidBody3D and body.get_parent() and body.get_parent().has_method("activate_ragdoll"):
		var passenger = body.get_parent()
		print("Passenger detected: ", passenger.name)
		
		# Only activate if the passenger is not already picked up or delivered
		if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
			print("Activating passenger ragdoll")
			passenger.activate_ragdoll(self, -1)
			emit_signal("passenger_hit", passenger)
			
			# Directly call the level manager's reset function
			var level_manager = get_node("/root/Main/LevelManager")
			if level_manager and level_manager.has_method("schedule_level_reset"):
				level_manager.schedule_level_reset(passenger)
	elif body.get_parent() and body.get_parent().has_method("is_passenger"):
		# If this is a passenger, add it to nearby passengers
		nearby_passengers.append(body.get_parent())
	elif body.get_parent() and body.get_parent().has_method("is_destination"):
		# If this is a destination, add it to nearby destinations
		nearby_destinations.append(body.get_parent())

func _on_pickup_area_body_exited(body: Node) -> void:
	# Remove destinations/passengers from the nearby lists when they exit
	if body.get_parent() and body.get_parent().has_method("is_passenger"):
		var idx = nearby_passengers.find(body.get_parent())
		if idx != -1:
			nearby_passengers.remove_at(idx)
	elif body.get_parent() and body.get_parent().has_method("is_destination"):
		var idx = nearby_destinations.find(body.get_parent())
		if idx != -1:
			nearby_destinations.remove_at(idx)

# UTILITY FUNCTIONS

func _handle_fall() -> void:
	print("Car fell off the edge, resetting level...")
	
	# Prevent multiple resets
	if reset_in_progress:
		return
		
	can_reset = false
	reset_in_progress = true
	
	# Immediately halt all movement
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Start the protection timer
	reset_protection_timer.start()
	
	# Call reset on the level manager
	var level_manager = get_node("/root/Main/LevelManager")
	if level_manager and level_manager.has_method("schedule_level_reset"):
		level_manager.schedule_level_reset()

func _on_reset_protection_timeout() -> void:
	can_reset = true
	reset_in_progress = false

# Reset physics state completely
func reset_physics_state() -> void:
	# Reset all flags and states
	is_driving = false
	turn_in_progress = false
	turn_queued = false
	reset_in_progress = false
	can_reset = true
	
	# Reset velocities
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Update direction based on rotation (important after teleporting)
	update_direction_from_rotation()
	
	print("Player physics state has been reset")

func clear_passengers() -> void:
	# Clean up any indicators for current passengers
	for passenger in current_passengers:
		if passenger and is_instance_valid(passenger):
			# If passenger has an indicator that was reparented, remove it
			if passenger.destination_indicator and passenger.destination_indicator.get_parent() != passenger:
				passenger.destination_indicator.queue_free()
	
	current_passengers.clear()
	nearby_passengers.clear()
	nearby_destinations.clear()

func check_level_completion() -> void:
	# Get the level from the main scene
	var level_manager = get_node("/root/Main/LevelManager")
	if not level_manager:
		return
	
	var current_level = level_manager.current_level_instance
	if not current_level:
		return
	
	# Check if all required passengers have been delivered
	var all_delivered = true
	for node in get_tree().get_nodes_in_group("passengers"):
		if not node.is_delivered and not node.is_ragdolling:
			all_delivered = false
			break
	
	# Also check if there are any passengers still in the car
	if current_passengers.size() > 0:
		all_delivered = false
	
	if all_delivered:
		print("All passengers delivered! Level completed.")
		emit_signal("level_completed")
		
		# Transition to next level if available
		if current_level.has_method("get") and current_level.get("next_level_path") != "":
			var next_level = current_level.next_level_path
			var transition_delay = 2.0
			
			if current_level.has_method("get") and current_level.get("transition_delay") > 0:
				transition_delay = current_level.transition_delay
			
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				emit_signal("door_entered", next_level, Vector2i(1, 1))
			)
