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
	
	# Initialize physics
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Enable wheel raycasts for ground detection
	if wheel_ray_fl:
		wheel_ray_fl.enabled = true
		wheel_ray_fl.target_position = Vector3(0, -0.5, 0)
	if wheel_ray_fr:
		wheel_ray_fr.enabled = true
		wheel_ray_fr.target_position = Vector3(0, -0.5, 0)
	if wheel_ray_bl:
		wheel_ray_bl.enabled = true
		wheel_ray_bl.target_position = Vector3(0, -0.5, 0)
	if wheel_ray_br:
		wheel_ray_br.enabled = true
		wheel_ray_br.target_position = Vector3(0, -0.5, 0)
	
	# Connect pickup area signals
	if pickup_area:
		# Set collision layer/mask for pickup area
		# Layer 4 for pickup area + detect passengers (layer 2), destinations (layer 8), and doors (layer 16)
		pickup_area.collision_layer = 4     # Layer 3 (player pickup area)
		pickup_area.collision_mask = 26     # Layers 2 (passengers) + 8 (destinations) + 16 (doors)
		
		print("Configured player pickup area with layer: ", pickup_area.collision_layer, 
			  " and mask: ", pickup_area.collision_mask)
		
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
	# Check if car is grounded and get wheel contact info
	var wheel_info = _check_grounded_detailed()
	is_grounded = wheel_info.grounded
	
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
		# This prevents wild spinning while still looking realistic
		if abs(rotation.x) > 0.8 or abs(rotation.z) > 0.8:
			# Apply gentle self-righting torque
			var correction_x = -rotation.x * 2.0
			var correction_z = -rotation.z * 2.0
			apply_torque(Vector3(correction_x, 0, correction_z))
	
	# Apply continuous driving force if needed (only when grounded)
	if is_driving and not turn_in_progress:
		# Ensure ground check is done each frame
		is_grounded = _check_grounded()
		
		if is_grounded:
			# Calculate current forward velocity
			var forward_velocity = current_direction.dot(linear_velocity)
			
			# Only apply force if below max speed
			if forward_velocity < max_velocity:
				# Apply less force as we approach max speed
				var speed_factor = clamp(1.0 - (forward_velocity / max_velocity), 0.1, 1.0)
				# Increased force multiplier for better acceleration
				apply_central_force(current_direction * move_speed * 60.0 * speed_factor)
				
				# Debug output to verify driving state
				if Engine.get_physics_frames() % 60 == 0:  # Print only occasionally to avoid spam
					print("Driving active - velocity: ", forward_velocity, " max: ", max_velocity)
	
	# Process turn queue if needed
	if turn_queued and not turn_in_progress:
		turn_queued = false
		_perform_turn()
	
	# Check for falling below threshold (with additional protection against multiple resets)
	if position.y < fall_threshold and can_reset and not reset_in_progress:
		_handle_fall()

# Simplified ground check (for compatibility with existing code)
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
		
		# Print detailed ground status occasionally for debugging
		if Engine.get_physics_frames() % 120 == 0:  # Every ~2 seconds
			print("Wheels on ground: ", result.wheels_on_ground, "/4 - ",
				  "F:", result.front_wheels_on_ground, "/2, ",
				  "B:", result.back_wheels_on_ground, "/2, ",
				  "L:", result.left_wheels_on_ground, "/2, ",
				  "R:", result.right_wheels_on_ground, "/2")
		
		# Consider the car grounded if at least 2 wheels are touching the ground
		result.grounded = result.wheels_on_ground >= 2
	else:
		# Fallback to direct raycast if wheel rays aren't available
		var ray_length = 0.4 # Adjust based on car height
		var space_state = get_world_3d().direct_space_state
		
		# Create a query for the raycast
		var query = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + Vector3(0, -ray_length, 0),
			1, # Collision mask (Layer 1)
			[get_rid()] # Exclude self
		)
		
		var query_result = space_state.intersect_ray(query)
		result.grounded = not query_result.is_empty()
		if result.grounded:
			result.wheels_on_ground = 4 # Simplification when using central ray
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
	
	# Force immediate ground check
	is_grounded = _check_grounded()
	
	# Only apply impulse if grounded
	if is_grounded:
		# Apply initial impulse to get moving immediately
		# Increased impulse multiplier for better initial movement
		apply_central_impulse(current_direction * move_speed * 0.8)
		print("Car started driving continuously (grounded)")
	else:
		# Even if not grounded now, keep driving flag on for when we touch ground
		print("Car started driving mode, but waiting for ground contact")

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
	# The wait function should only pause script execution without changing the car's movement
	
	print("Waiting for ", seconds, " seconds")
	await get_tree().create_timer(seconds).timeout
	
	print("Wait complete, continuing script execution")

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
	
	# Note: We don't need to handle door exit since door entry immediately triggers level transition

# Handle direct collisions between player car and other objects
func _on_player_body_entered(body: Node) -> void:
	print("Player directly collided with: ", body.name)
	
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
	
	# Don't immediately halt movement - let physics play out
	# We'll reset after a delay to show the falling animation
	
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
			
			print("Next level path: ", next_level)
			
			var transition_delay = 2.0
			
			if current_level.has_method("get") and current_level.get("transition_delay") > 0:
				transition_delay = current_level.transition_delay
			
			print("Level completion - scheduling transition to " + next_level + " in " + str(transition_delay) + " seconds")
			
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				print("Level transition timer expired, emitting door_entered signal")
				emit_signal("door_entered", next_level, Vector2i(1, 1))
			)
