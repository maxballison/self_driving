extends RigidBody3D

# Movement variables
var is_driving: bool = false
var move_speed: float = 5.0  # Units per second
var is_turning: bool = false
var can_reset: bool = true

# Direction vector (normalized)
var current_direction_vec: Vector3 = Vector3(1, 0, 0)  # Default: facing East

# Fall detection
var fall_threshold: float = -10.0  # Y position below which the car is considered fallen

# Wheel raycast properties
var suspension_rest_length: float = 0.5
var suspension_stiffness: float = 500.0
var suspension_damping: float = 100.0
var wheel_mass: float = 10.0
var ground_friction: float = 50.0

# Passenger tracking
var current_passengers: Array = []
var max_passengers: int = 3
var nearby_passengers: Array = []
var nearby_destinations: Array = []

# References to components
@onready var pickup_area = $PassengerPickupArea
@onready var car_model = $CarModel
@onready var reset_protection_timer = $ResetProtectionTimer

# Wheel raycasts
@onready var wheel_ray_fl = $WheelRayFL
@onready var wheel_ray_fr = $WheelRayFR
@onready var wheel_ray_bl = $WheelRayBL
@onready var wheel_ray_br = $WheelRayBR
var wheel_rays = []

# Signals
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)
signal passenger_hit(passenger)
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger, destination)
signal level_completed()

func _ready() -> void:
	# Initialize wheel raycasts
	wheel_rays = [wheel_ray_fl, wheel_ray_fr, wheel_ray_bl, wheel_ray_br]
	
	# Set initial direction vector based on rotation
	update_direction_from_rotation()
	
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
	
	clear_passengers()
	
	# Set initial wheel ray lengths
	for ray in wheel_rays:
		ray.target_position.y = -suspension_rest_length

func _physics_process(delta: float) -> void:
	# Apply suspension forces for each wheel
	apply_wheel_physics(delta)
	
	# Keep the car's rotation clean (prevent rolling on sides)
	var current_rot = rotation
	rotation = Vector3(0, current_rot.y, 0)
	
	# Limit angular velocity to prevent excessive spinning
	angular_velocity.x = 0
	angular_velocity.z = 0
	
	# Check for falling below threshold
	if position.y < fall_threshold and can_reset:
		_handle_fall()

func apply_wheel_physics(delta: float) -> void:
	var wheels_on_ground = 0
	var driving_force_multiplier = 0
	
	# Track how many wheels are touching the ground
	for ray in wheel_rays:
		if ray.is_colliding():
			wheels_on_ground += 1
			
			# Apply suspension forces
			var hit_point = ray.get_collision_point()
			var surface_normal = ray.get_collision_normal()
			var current_length = (global_transform.origin + ray.position - hit_point).length() 
			var spring_force = suspension_stiffness * (suspension_rest_length - current_length)
			
			# Calculate and apply the suspension force
			var force_direction = -surface_normal
			var force = force_direction * spring_force
			
			# Apply the force at the wheel's position
			apply_force(force, ray.position)
			
			# Calculate the driving force direction based on our current direction
			if is_driving and not is_turning:
				# Apply driving force along the ground plane (perpendicular to surface normal)
				var drive_dir = current_direction_vec.slide(surface_normal).normalized()
				var drive_force = drive_dir * move_speed * 200.0 * delta
				
				# Apply driving force
				apply_force(drive_force, ray.position)
				driving_force_multiplier += 1
			
			# Apply friction to prevent sliding
			var lateral_vel = linear_velocity.slide(surface_normal)
			var friction_force = -lateral_vel.normalized() * lateral_vel.length() * ground_friction * delta
			apply_central_force(friction_force)
	
	# Car is in air - no driving forces
	if wheels_on_ground == 0 and is_driving:
		# Apply a small directional push while airborne to maintain some control
		apply_central_force(current_direction_vec * move_speed * 20.0 * delta)
	
	# Apply stronger driving force if fewer wheels are on the ground
	# This helps the car drive off ledges more easily
	if driving_force_multiplier > 0:
		var boost_factor = 4.0 / driving_force_multiplier  # Scale up force when fewer wheels touching
		apply_central_force(current_direction_vec * move_speed * 100.0 * boost_factor * delta)

func update_direction_from_rotation() -> void:
	# Calculate direction vector from rotation
	current_direction_vec = Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y).normalized()
	print("Direction updated: ", current_direction_vec)

# COMMAND FUNCTIONS

func drive() -> void:
	is_driving = true
	print("Car started driving continuously")

func stop() -> void:
	is_driving = false
	print("Car stopped")
	
	# Apply braking force
	apply_central_force(-linear_velocity.normalized() * 500.0)

func turn_left() -> void:
	if is_turning:
		return
	
	is_turning = true
	
	# Stop current movement during turn
	var prev_driving = is_driving
	is_driving = false
	
	# Rotate immediately
	rotation.y += PI/2
	update_direction_from_rotation()
	
	# Small delay to allow physics to update
	await get_tree().create_timer(0.05).timeout
	
	# Resume driving if we were driving before
	is_turning = false
	is_driving = prev_driving
	
	print("Turned left by 90 degrees")

func turn_right() -> void:
	if is_turning:
		return
	
	is_turning = true
	
	# Stop current movement during turn
	var prev_driving = is_driving
	is_driving = false
	
	# Rotate immediately
	rotation.y -= PI/2
	update_direction_from_rotation()
	
	# Small delay to allow physics to update
	await get_tree().create_timer(0.05).timeout
	
	# Resume driving if we were driving before
	is_turning = false
	is_driving = prev_driving
	
	print("Turned right by 90 degrees")

func wait(seconds: float) -> void:
	# Create a timer to pause execution
	var prev_driving = is_driving
	is_driving = false
	print("Waiting for ", seconds, " seconds")
	
	await get_tree().create_timer(seconds).timeout
	
	# Resume previous state if we were driving
	is_driving = prev_driving
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
	can_reset = false
	reset_protection_timer.start()
	
	# Call reset on the level manager
	var level_manager = get_node("/root/Main/LevelManager")
	if level_manager and level_manager.has_method("schedule_level_reset"):
		level_manager.schedule_level_reset()

func _on_reset_protection_timeout() -> void:
	can_reset = true

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
