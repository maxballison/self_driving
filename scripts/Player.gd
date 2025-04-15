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

# New driving mechanics
var target_distance: float = 0.0  # Distance the car aims to travel
var current_drive_units: int = 0  # Number of drive commands issued
var unit_distance: float = 1.0  # One "unit" of distance
var natural_friction: float = 0.2  # Even less friction (was 0.3)
var last_grounded_position: Vector3 = Vector3.ZERO # Track last known good position

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

# Debug variables
var debug_stop_reason: String = ""
var last_velocity: Vector3 = Vector3.ZERO
var velocity_changed_abruptly: bool = false

# References to components
@onready var pickup_area = $PassengerPickupArea
@onready var car_model = $CarModel
@onready var reset_protection_timer = $ResetProtectionTimer
@onready var wheel_ray_fl = $WheelRayFL
@onready var wheel_ray_fr = $WheelRayFR
@onready var wheel_ray_bl = $WheelRayBL
@onready var wheel_ray_br = $WheelRayBR

# Signals
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)
signal passenger_hit(passenger)
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger, destination)
signal level_completed()

func _ready() -> void:
	# Set initial direction based on rotation
	update_direction_from_rotation()
	
	# Create a physics material with low friction
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = 0.01  # Extremely low friction for better sliding
	physics_mat.bounce = 0.1    # Slight bounce
	physics_material_override = physics_mat
	
	# Initialize physics
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Record initial position as the first grounded position
	last_grounded_position = global_position
	
	# Enable wheel raycasts for ground detection
	for ray in [wheel_ray_fl, wheel_ray_fr, wheel_ray_bl, wheel_ray_br]:
		if ray:
			ray.enabled = true
			ray.target_position = Vector3(0, -0.6, 0)  # Slightly longer raycast
	
	# Connect pickup area signals
	if pickup_area:
		# Set collision layer/mask for pickup area
		pickup_area.collision_layer = 4     # Layer 3 (player pickup area)
		pickup_area.collision_mask = 26     # Layers 2 (passengers) + 8 (destinations) + 16 (doors)
		
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
	
	# Connect direct collision signal
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_player_body_entered)
	
	clear_passengers()

func _physics_process(delta: float) -> void:
	# Store previous velocity to detect sudden changes
	var prev_velocity = linear_velocity
	
	# Check if car is grounded and get wheel contact info
	var wheel_info = _check_grounded_detailed()
	var was_grounded = is_grounded
	is_grounded = wheel_info.grounded
	
	# Update last good position if grounded
	if is_grounded:
		last_grounded_position = global_position
	
	# Check for abrupt velocity changes
	if prev_velocity.length() > 1.0 and linear_velocity.length() < 0.2 and not turn_in_progress:
		velocity_changed_abruptly = true
		debug_stop_reason = "Velocity dropped suddenly: " + str(prev_velocity.length()) + " to " + str(linear_velocity.length())
		# Apply a small impulse in the direction we were moving to overcome small obstacles
		apply_central_impulse(prev_velocity.normalized() * 1.0)
	else:
		velocity_changed_abruptly = false
	
	# Apply natural friction when grounded to slow down car naturally
	if is_grounded and not turn_in_progress:
		# Calculate current forward velocity and lateral velocity
		var forward_velocity = current_direction.dot(linear_velocity)
		var lateral_velocity = linear_velocity - current_direction * forward_velocity
		
		# Apply gentler lateral friction (allow more sliding)
		if lateral_velocity.length() > 0.2:
			# Reduced lateral friction by lowering force multiplier
			apply_central_force(-lateral_velocity.normalized() * lateral_velocity.length() * 0.3)
		
		# Apply very gradual forward friction
		if forward_velocity > 0.2:  # Only apply friction when moving
			var friction_force = -current_direction * forward_velocity * natural_friction * delta * 60.0
			apply_central_force(friction_force)
		elif abs(forward_velocity) < 0.02:  # Extremely low threshold for stopping completely
			# Instead of zeroing velocity, just apply a very tiny slowdown
			linear_velocity *= 0.95
	
	# Detect if car is at an edge (some wheels on ground, some not)
	var at_edge = wheel_info.wheels_on_ground > 0 and wheel_info.wheels_on_ground < 4
	var wheels_front = wheel_info.front_wheels_on_ground
	var wheels_back = wheel_info.back_wheels_on_ground
	var wheels_left = wheel_info.left_wheels_on_ground
	var wheels_right = wheel_info.right_wheels_on_ground
	
	# Handle physics based on car position
	if is_grounded and not at_edge:
		# Fully on ground - keep upright
		var current_rot = rotation
		rotation = Vector3(0, current_rot.y, 0)
		
		# Prevent flipping by zeroing out x and z angular velocity
		angular_velocity.x = 0
		angular_velocity.z = 0
	elif at_edge:
		# At an edge - allow some tilting based on which wheels are grounded
		var current_rot = rotation
		
		# Allow natural tilting while preserving general direction
		if abs(rotation.x) > 1.2 or abs(rotation.z) > 1.2:
			# Prevent extreme flipping by applying some dampening
			angular_velocity *= 0.9
		
		# If front wheels are off but back wheels on, allow front to dip
		if wheels_back > 0 and wheels_front == 0:
			# Apply a gentle torque to simulate front tipping over edge
			apply_torque(Vector3(5.0, 0, 0))
		
		# Same for left/right side tilting
		if wheels_right > 0 and wheels_left == 0:
			apply_torque(Vector3(0, 0, -5.0))
		elif wheels_left > 0 and wheels_right == 0:
			apply_torque(Vector3(0, 0, 5.0))
	else:
		# Completely in air - full physics, but with slight auto-leveling
		if abs(rotation.x) > 0.8 or abs(rotation.z) > 0.8:
			# Apply gentle self-righting torque
			var correction_x = -rotation.x * 2.0
			var correction_z = -rotation.z * 2.0
			apply_torque(Vector3(correction_x, 0, correction_z))
	
	# Process turn queue if needed
	if turn_queued and not turn_in_progress:
		turn_queued = false
		_perform_turn()
	
	# Check for falling below threshold
	if position.y < fall_threshold and can_reset and not reset_in_progress:
		_handle_fall()
	
	# Debug output occasionally
	if Engine.get_physics_frames() % 60 == 0:
		print("Velocity: ", linear_velocity.length(), " | Grounded: ", is_grounded, 
			  " | Wheels: ", wheel_info.wheels_on_ground)
		if velocity_changed_abruptly:
			print("STOP DETECTED: ", debug_stop_reason)
	
	# Store current velocity for next frame comparison
	last_velocity = linear_velocity

# Simplified ground check
func _check_grounded() -> bool:
	var info = _check_grounded_detailed()
	return info.grounded

# Detailed ground check providing wheel contact information
func _check_grounded_detailed() -> Dictionary:
	var result = {
		"grounded": false,
		"wheels_on_ground": 0,
		"front_wheels_on_ground": 0,
		"back_wheels_on_ground": 0,
		"left_wheels_on_ground": 0,
		"right_wheels_on_ground": 0,
		"wheel_fl": false,
		"wheel_fr": false,
		"wheel_bl": false,
		"wheel_br": false
	}
	
	# Use the wheel raycasts to check if the car is grounded
	if wheel_ray_fl and wheel_ray_fr and wheel_ray_bl and wheel_ray_br:
		# Check each wheel independently
		if wheel_ray_fl.is_colliding():
			result.wheels_on_ground += 1
			result.front_wheels_on_ground += 1
			result.left_wheels_on_ground += 1
			result.wheel_fl = true
			
		if wheel_ray_fr.is_colliding():
			result.wheels_on_ground += 1
			result.front_wheels_on_ground += 1
			result.right_wheels_on_ground += 1
			result.wheel_fr = true
			
		if wheel_ray_bl.is_colliding():
			result.wheels_on_ground += 1
			result.back_wheels_on_ground += 1
			result.left_wheels_on_ground += 1
			result.wheel_bl = true
			
		if wheel_ray_br.is_colliding():
			result.wheels_on_ground += 1
			result.back_wheels_on_ground += 1
			result.right_wheels_on_ground += 1
			result.wheel_br = true
		
		# Consider the car grounded if at least 1 wheel is touching the ground (was 2)
		result.grounded = result.wheels_on_ground >= 1
	else:
		# Fallback to direct raycast if wheel rays aren't available
		var ray_length = 0.4
		var space_state = get_world_3d().direct_space_state
		
		var query = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + Vector3(0, -ray_length, 0),
			1,
			[get_rid()]
		)
		
		var query_result = space_state.intersect_ray(query)
		result.grounded = not query_result.is_empty()
		if result.grounded:
			result.wheels_on_ground = 4
			result.front_wheels_on_ground = 2
			result.back_wheels_on_ground = 2
			result.left_wheels_on_ground = 2
			result.right_wheels_on_ground = 2
			result.wheel_fl = true
			result.wheel_fr = true
			result.wheel_bl = true
			result.wheel_br = true
	
	return result

func update_direction_from_rotation() -> void:
	current_direction = Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y).normalized()

# Perform turn
func _perform_turn() -> void:
	if turn_in_progress:
		return
	
	turn_in_progress = true
	
	# Store current velocity magnitude for restoration after turn
	var current_speed = linear_velocity.length()
	
	# Apply gentler braking force for more slide during turns
	var brake_force = -linear_velocity * 2.0  # Even gentler braking
	apply_central_force(brake_force)
	
	# Rotate based on direction
	rotation.y += PI/2 * turn_direction
	update_direction_from_rotation()
	
	# Apply impulse in new direction proportional to previous speed
	if is_grounded:
		var turn_impulse = min(current_speed * 0.7, move_speed * 0.2)
		apply_central_impulse(current_direction * turn_impulse)
	
	# Complete turn after a short delay
	await get_tree().create_timer(0.15)
	turn_in_progress = false

# COMMAND FUNCTIONS

func drive() -> void:
	# Force immediate ground check
	is_grounded = _check_grounded()
	
	# Only apply impulse if grounded
	if is_grounded:
		# Calculate current forward velocity
		var forward_velocity = current_direction.dot(linear_velocity)
		
		# Increment drive units
		current_drive_units += 1
		target_distance = current_drive_units * unit_distance
		
		# Calculate impulse strength based on current velocity
		var impulse_strength = move_speed * 1
		
		# Reduce impulse if approaching max speed
		if forward_velocity > max_velocity * 0.6:
			impulse_strength *= (1.0 - (forward_velocity / max_velocity))
		
		# Apply impulse for discrete movement
		apply_central_impulse(current_direction * impulse_strength)
		print("Car moving forward - impulse applied, drive units: ", current_drive_units)
	else:
		# If recently grounded but now airborne, still try to move
		var time_since_impulse = get_tree().get_frames() % 10
		if time_since_impulse < 5 and (global_position - last_grounded_position).length() < 1.0:
			apply_central_impulse(current_direction * move_speed * 0.4)
			print("Car moving in air from recent ground contact")
		else:
			print("Car not grounded - cannot move forward")

func stop() -> void:
	# Apply lighter braking force for more gradual stops
	var brake_force = -linear_velocity.normalized() * linear_velocity.length() * 4.0
	apply_central_force(brake_force)
	
	# Reset drive units
	current_drive_units = 0
	target_distance = 0.0
	print("Car slowing down - drive units reset")

func turn_left() -> void:
	turn_direction = 1
	turn_queued = true
	print("Turn left queued")

func turn_right() -> void:
	turn_direction = -1
	turn_queued = true
	print("Turn right queued")

func wait(seconds: float) -> void:
	print("Waiting for ", seconds, " seconds")
	await get_tree().create_timer(seconds).timeout
	print("Wait complete")

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
	
	# Better passenger detection logic
	var passenger = null
	
	# Direct passenger detection (main passenger body)
	if body.has_method("is_passenger"):
		passenger = body
	# Fallback for passenger child nodes
	elif body.get_parent() and body.get_parent().has_method("is_passenger"):
		passenger = body.get_parent()
	
	# Process passenger if found
	if passenger:
		if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
			print("Adding passenger to nearby passengers list: ", passenger.name)
			if not nearby_passengers.has(passenger):
				nearby_passengers.append(passenger)
	
	# Handle destinations with improved detection
	var destination = null
	
	# Try multiple detection methods
	if body.has_method("is_destination"):
		# Direct method presence
		destination = body
		print("Detected destination directly via method: ", body.name)
	elif body.get_parent() and body.get_parent().has_method("is_destination"):
		# Parent has the method
		destination = body.get_parent()
		print("Detected destination via parent: ", body.get_parent().name)
	elif body.has_node("DeliveryArea") or (body.get_parent() and body.get_parent().has_node("DeliveryArea")):
		# Has delivery area node
		if body.has_node("DeliveryArea"):
			destination = body
			print("Detected destination via DeliveryArea node: ", body.name)
		else:
			destination = body.get_parent()
			print("Detected destination via parent DeliveryArea: ", body.get_parent().name)
	
	# Add destination to nearby list if found
	if destination and not nearby_destinations.has(destination):
		print("Adding destination to nearby destinations list: ", destination.name)
		nearby_destinations.append(destination)
	
	# Handle door detection
	var door = null
	
	# Try multiple detection methods for doors (similar to destinations)
	if body.has_method("is_door"):
		# Direct method presence
		door = body
		print("Detected door directly via method: ", body.name)
	elif body.get_parent() and body.get_parent().has_method("is_door"):
		# Parent has the method
		door = body.get_parent()
		print("Detected door via parent: ", body.get_parent().name)
	elif body.has_node("DoorArea") or (body.get_parent() and body.get_parent().has_node("DoorArea")):
		# Has door area node
		if body.has_node("DoorArea"):
			door = body
			print("Detected door via DoorArea node: ", body.name)
		else:
			door = body.get_parent()
			print("Detected door via parent DoorArea: ", body.get_parent().name)
	
	# If door found, trigger transition immediately
	if door and door.has_method("_on_door_area_body_entered"):
		print("Processing door entry from pickup area detection")
		door._on_door_area_body_entered(self)

func _on_pickup_area_body_exited(body: Node) -> void:
	# Remove destinations/passengers from the nearby lists when they exit using improved detection
	
	# Find passenger using same logic as in body_entered
	var passenger = null
	if body.has_method("is_passenger"):
		passenger = body
	elif body.get_parent() and body.get_parent().has_method("is_passenger"):
		passenger = body.get_parent()
	
	# Remove passenger if found
	if passenger:
		var idx = nearby_passengers.find(passenger)
		if idx != -1:
			print("Removing passenger from nearby list: ", passenger.name)
			nearby_passengers.remove_at(idx)
	
	# Find destination using same logic as in body_entered
	var destination = null
	if body.has_method("is_destination"):
		destination = body
	elif body.get_parent() and body.get_parent().has_method("is_destination"):
		destination = body.get_parent()
	
	# Remove destination if found
	if destination:
		var idx = nearby_destinations.find(destination)
		if idx != -1:
			nearby_destinations.remove_at(idx)

# Handle direct collisions between player car and other objects
func _on_player_body_entered(body: Node) -> void:
	print("Player directly collided with: ", body.name)
	
	# If we're moving at a reasonable speed, apply a small bounce impulse
	if linear_velocity.length() > 1.0:
		# Calculate bounce direction - away from collision point
		var bounce_dir = global_position - body.global_position
		bounce_dir.y = 0  # Keep bounce horizontal
		bounce_dir = bounce_dir.normalized()
		
		# Apply a small bounce impulse
		apply_central_impulse(bounce_dir * 2.0)
	
	# Improved passenger detection logic for collisions
	var passenger = null
	
	# Try various ways to find the actual passenger
	if body.has_method("is_passenger") or "passenger" in body.name.to_lower():
		# Direct passenger object (SimplePassenger is the passenger itself)
		passenger = body
		print("Direct passenger collision detected: ", body.name)
	elif body.get_parent() and (body.get_parent().has_method("is_passenger") or "passenger" in body.get_parent().name.to_lower()):
		# Parent is passenger (PassengerPhysics case)
		passenger = body.get_parent()
		print("Parent passenger collision detected: ", body.get_parent().name)
	
	if passenger:
		print("Player hit passenger: ", passenger.name)
		
		# Check if passenger has the activate_ragdoll method
		if passenger.has_method("activate_ragdoll"):
			# Only activate ragdoll if not already in special state
			if not ("is_picked_up" in passenger and passenger.is_picked_up) and \
			   not ("is_delivered" in passenger and passenger.is_delivered) and \
			   not ("is_ragdolling" in passenger and passenger.is_ragdolling):
				# Activate passenger ragdoll physics
				print("Activating ragdoll for: ", passenger.name)
				passenger.activate_ragdoll(self, -1)
				emit_signal("passenger_hit", passenger)
				
				# Play sound effect if available
				var main = get_node_or_null("/root/Main")
				if main and main.has_method("play_sound"):
					main.play_sound("crash", -5, 0.9 + randf() * 0.2)
				
				# Schedule a level reset (with delay to see physics effects)
				var level_manager = get_node("/root/Main/LevelManager")
				if level_manager and level_manager.has_method("schedule_level_reset"):
					level_manager.schedule_level_reset(passenger)

# UTILITY FUNCTIONS

func _handle_fall() -> void:
	print("Car fell off the edge, resetting level...")
	
	# Prevent multiple resets
	if reset_in_progress:
		return
		
	can_reset = false
	reset_in_progress = true
	
	# Apply a slight random spin for more dramatic falling effect
	var random_torque = Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-1.0, 1.0),
		randf_range(-3.0, 3.0)
	)
	apply_torque(random_torque)
	
	# Start the protection timer with a longer delay for fall animation
	reset_protection_timer.wait_time = 1.5  # Longer delay to show falling
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
	
	# Reset drive units counter
	current_drive_units = 0
	target_distance = 0.0
	
	# Reset velocities
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Force upright orientation, keeping only Y rotation
	var current_y_rotation = rotation.y
	rotation = Vector3(0, current_y_rotation, 0)
	
	# Update direction based on rotation (important after teleporting)
	update_direction_from_rotation()
	
	# Apply a small upward impulse to prevent floor clipping
	apply_central_impulse(Vector3(0, 1.0, 0))
	
	# Update last grounded position
	last_grounded_position = global_position
	
	# Reset debug variables
	debug_stop_reason = ""
	velocity_changed_abruptly = false
	
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
			
			# Make sure the path is properly formatted with "res://" prefix if needed
			if not next_level.begins_with("res://") and not next_level.begins_with("/"):
				next_level = "res://GeneratedLevels/" + next_level
			
			var transition_delay = 2.0
			
			if current_level.has_method("get") and current_level.get("transition_delay") > 0:
				transition_delay = current_level.transition_delay
			
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				emit_signal("door_entered", next_level, Vector2i(1, 1))
			)
