extends Node3D

# Grid positions and level data
var grid_position: Vector2i = Vector2i(0, 0)
var grid_width: int
var grid_height: int
var cell_size: float
var tile_data: Array = []  # 2D array of blueprint chars
var door_map: Dictionary = {}  # (x,y) -> door node

# New passenger tracking
var passenger_map: Dictionary = {}  # (x,y) -> passenger node
var destination_map: Dictionary = {}  # (x,y) -> destination node
var current_passengers: Array = []  # Array of Passenger objects
var max_passengers: int = 3  # Maximum number of passengers the car can hold
var nearby_passengers: Array = []  # Track passengers within pickup range

# Signals
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)
signal passenger_hit(passenger)
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger, destination)
signal level_completed()

# Direction enum (clockwise order)
enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }
var current_direction: int = Direction.EAST  # Default: car starts facing north

# Variables for smooth movement animation
var is_moving: bool = false
var is_turning: bool = false
var move_start: Vector3         # starting position before move
var move_target: Vector3        # target position after move
var rotation_start: float       # starting rotation before turn
var rotation_target: float      # target rotation after turn
var animation_time: float = 0.0 # elapsed time since animation started
var should_teleport: bool = true  # Flag for instant teleportation

# Physics car body
@onready var car_physics = $CarPhysicsBody
@onready var pickup_area = $PassengerPickupArea

func _ready() -> void:
	# Set collision layer for car physics
	if car_physics:
		car_physics.collision_layer = 4  # Layer 3
		car_physics.collision_mask = 2   # Layer 2 (passengers)
	
	# Connect passenger pickup area signals
	if pickup_area:
		# Make sure the pickup area can detect passenger collisions
		pickup_area.collision_mask = 2  # Layer 2 (passengers)
		pickup_area.monitoring = true
		
		# Connect the body_entered signal to detect collisions
		if not pickup_area.is_connected("body_entered", Callable(self, "_on_pickup_area_body_entered")):
			pickup_area.connect("body_entered", Callable(self, "_on_pickup_area_body_entered"))
	
	update_world_position()
	update_model_rotation()
	clear_passengers()
	
	refresh_nearby_passengers()

func clear_passengers() -> void:
	# Clean up any indicators for current passengers
	for passenger in current_passengers:
		if passenger and is_instance_valid(passenger):
			# If passenger has an indicator that was reparented, remove it
			if passenger.destination_indicator and passenger.destination_indicator.get_parent() != passenger:
				passenger.destination_indicator.queue_free()
	
	current_passengers.clear()
	nearby_passengers.clear()

# Function to drive forward in the direction the car is facing
func drive() -> void:
	if is_moving or is_turning:
		# Prevent starting a new move until the current one finishes.
		return
		
	var new_pos = grid_position
	match current_direction:
		Direction.NORTH:
			new_pos.y -= 1
		Direction.SOUTH:
			new_pos.y += 1
		Direction.EAST:
			new_pos.x += 1
		Direction.WEST:
			new_pos.x -= 1
			
	# Check boundaries
	if new_pos.x < 0 or new_pos.x >= grid_width or new_pos.y < 0 or new_pos.y >= grid_height:
		print("Blocked: out of bounds")
		return
		
	# Check tile_data for walls
	var tile_char = tile_data[new_pos.y][new_pos.x]  # e.g. ' ', '#', 'd'
	if tile_char == '#' or tile_char == 'x':
		print("Blocked: wall present")
		return
	
	grid_position = new_pos
	
	# Legacy door code - keep for compatibility
	if tile_char == 'd':
		var door_node = door_map.get(new_pos, null)
		if door_node:
			if door_node.has_method("get"):
				# Set the teleport flag to true for door transitions
				should_teleport = true
				
				# Attempt to read the door script's exports
				var next_level = door_node.get("next_level_path")
				var spawn_pos: Vector2i = door_node.get("next_level_spawn")
				print("Stepped on a door at ", new_pos, ". Next level: ", next_level)
				emit_signal("door_entered", next_level, spawn_pos)
				grid_position = spawn_pos
			else:
				print("Door node found, but missing door script. No next_level data.")
				
	# Start the movement towards the new grid position
	update_world_position()
	
	# Update nearby_passengers list after moving
	refresh_nearby_passengers()

# Function to turn the car left (counter-clockwise)
func turn_left() -> void:
	if is_moving or is_turning:
		return
		
	# Update direction (subtract 1 with wrap-around)
	current_direction = (current_direction - 1 + 4) % 4
	start_turn_animation()
	print("Turned left: now facing " + Direction.keys()[current_direction])
	
	# Update nearby_passengers list after turning
	refresh_nearby_passengers()

# Function to turn the car right (clockwise)
func turn_right() -> void:
	if is_moving or is_turning:
		return
		
	# Update direction (add 1 with wrap-around)
	current_direction = (current_direction + 1) % 4
	start_turn_animation()
	print("Turned right: now facing " + Direction.keys()[current_direction])
	
	# Update nearby_passengers list after turning
	refresh_nearby_passengers()

# New function: pick up a passenger
func pick_up() -> bool:
	if is_moving or is_turning:
		return false
	
	if current_passengers.size() >= max_passengers:
		print("Car is full! Cannot pick up more passengers.")
		return false
	
	# Check for passengers in pickup range
	if nearby_passengers.size() > 0:
		for passenger in nearby_passengers:
			if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
				if passenger.pick_up(self):
					current_passengers.append(passenger)
					print("Picked up passenger going to destination ", passenger.destination_id)
					emit_signal("passenger_picked_up", passenger)
					
					# Update nearby passengers after pickup
					refresh_nearby_passengers()
					return true
	
	print("No passengers to pick up nearby!")
	return false

# New function: deliver a passenger
func drop_off() -> bool:
	if is_moving or is_turning:
		return false
	
	if current_passengers.size() == 0:
		print("No passengers in car to drop off!")
		return false
	
	# Check adjacent cells for destinations
	var positions_to_check = get_adjacent_positions()
	
	for pos in positions_to_check:
		if destination_map.has(pos):
			var destination = destination_map[pos]
			
			# Find a passenger that matches this destination
			for i in range(current_passengers.size()):
				var passenger = current_passengers[i]
				if passenger.destination_id == destination.destination_id:
					if passenger.deliver():  # Note: still using passenger.deliver() for compatibility
						# Remove from current passengers array
						current_passengers.remove_at(i)
						
						# Remove from passenger_map (important to prevent collision after delivery)
						for map_pos in passenger_map:
							if passenger_map[map_pos] == passenger:
								passenger_map.erase(map_pos)
								break
								
						destination.complete_delivery()
						print("Dropped off passenger at destination ", destination.destination_id)
						emit_signal("passenger_delivered", passenger, destination)
						
						# Check if all passengers have been delivered
						check_level_completion()
						
						# Update nearby passengers after delivery
						refresh_nearby_passengers()
						return true
	
	print("No matching destination nearby for any passenger!")
	return false

# Get positions adjacent to the car
func get_adjacent_positions() -> Array:
	var positions = []
	
	# Add all four directions
	positions.append(Vector2i(grid_position.x, grid_position.y - 1))  # North
	positions.append(Vector2i(grid_position.x + 1, grid_position.y))  # East
	positions.append(Vector2i(grid_position.x, grid_position.y + 1))  # South
	positions.append(Vector2i(grid_position.x - 1, grid_position.y))  # West
	
	# Filter out invalid positions
	var valid_positions = []
	for pos in positions:
		if pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height:
			if tile_data[pos.y][pos.x] != '#' and tile_data[pos.y][pos.x] != 'x':
				valid_positions.append(pos)
	
	return valid_positions

# Check which passengers are in pickup range
func refresh_nearby_passengers() -> void:
	nearby_passengers.clear()
	
	var adjacent_positions = get_adjacent_positions()
	for pos in adjacent_positions:
		if passenger_map.has(pos):
			var passenger = passenger_map[pos]
			if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
				nearby_passengers.append(passenger)

# Check if all passengers have been delivered
# Check if all passengers have been delivered
# Replace the entire check_level_completion function in Player.gd with this:

func check_level_completion() -> void:
	# Get the level from the main scene
	var level_manager = get_node("/root/Main/LevelManager")
	if not level_manager:
		return
	
	var current_level = level_manager.current_level_instance
	if not current_level:
		return
		
	# Count remaining passengers in the level
	var all_passengers_delivered = true
	
	for pos in passenger_map:
		var passenger = passenger_map[pos]
		if not passenger.is_delivered and not passenger.is_ragdolling:
			all_passengers_delivered = false
			break
	
	# Check current passengers in car
	if current_passengers.size() > 0:
		all_passengers_delivered = false
	
	if all_passengers_delivered:
		print("All passengers delivered! Level completed.")
		emit_signal("level_completed")
		
		# Get next level information from the level itself
		var next_level = current_level.next_level_path
		
		# If next_level_path is empty, try to find it from a door
		if next_level == "":
			# Find a door to use for next level info as a fallback
			for door_pos in door_map:
				var door = door_map[door_pos]
				if door.has_method("get"):
					next_level = door.get("next_level_path")
					break
		
		# Go to next level after a delay if we have a path
		if next_level != "":
			print("Transitioning to next level after delay: ", next_level)
			
			# Create a transition effect (e.g., fade or message)
			# For simplicity, we'll just use a timer
			var transition_delay = current_level.transition_delay
			if transition_delay <= 0:
				transition_delay = 2.0 # Default delay
				
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				# Just pass the next level path - spawn position will be determined by the level itself
				emit_signal("door_entered", next_level, Vector2i(1, 1))
			)

# Helper function to start the turn animation
func start_turn_animation() -> void:
	rotation_start = rotation.y
	rotation_target = direction_to_rotation(current_direction)
	
	# Ensure we take the shortest path when rotating
	if abs(rotation_target - rotation_start) > PI:
		if rotation_target > rotation_start:
			rotation_start += 2 * PI
		else:
			rotation_target += 2 * PI
			
	animation_time = 0.0
	is_turning = true

# Convert direction enum to Y-axis rotation in radians
func direction_to_rotation(dir: int) -> float:
	match dir:
		Direction.NORTH:
			return 0.0        # 0 degrees - facing negative Z
		Direction.EAST:
			return -PI * 0.5  # -90 degrees - facing positive X
		Direction.SOUTH:
			return -PI        # -180 degrees - facing positive Z
		Direction.WEST:
			return -PI * 1.5  # -270 degrees - facing negative X
	return 0.0

# Update the model's rotation based on current direction
func update_model_rotation() -> void:
	rotation.y = direction_to_rotation(current_direction)
	
	# Also update the physics body rotation
	if car_physics:
		car_physics.rotation.y = rotation.y

func update_world_position() -> void:
	if should_teleport:
		# Instantly teleport when transitioning levels
		position = Vector3(
			float(grid_position.x) * cell_size,
			0.2,  # Lowered Y position for car
			float(grid_position.y) * cell_size
		)
		is_moving = false
		should_teleport = false  # Reset the flag
		update_model_rotation()  # Make sure car is facing the right direction
		print("Car teleported to grid coord:", grid_position)
	else:
		# Normal gliding animation for regular moves
		move_start = position
		move_target = Vector3(
			float(grid_position.x) * cell_size,
			0.2,  # Lowered Y position for car
			float(grid_position.y) * cell_size
		)
		animation_time = 0.0
		is_moving = true
		print("Car moving to grid coord:", grid_position)

func _process(delta: float) -> void:
	if is_moving:
		animation_time += delta
		var t = animation_time / owner.run_delay
		
		# Clamp t to 1.0 so we don't overshoot.
		if t >= 1.0:
			t = 1.0
			is_moving = false
			
		# Linear interpolation between start and target positions
		position = move_start.lerp(move_target, t)
		
		# Update the physics body position
		if car_physics:
			car_physics.global_position = position
	
	if is_turning:
		animation_time += delta
		var t = animation_time / (owner.run_delay * 0.5)  # Half the time of movement
		
		if t >= 1.0:
			t = 1.0
			is_turning = false
			rotation.y = rotation_target  # Ensure perfect alignment
		else:
			# Use a smooth rotation using lerp_angle
			rotation.y = lerp_angle(rotation_start, rotation_target, t)
			
		# Update the physics body rotation
		if car_physics:
			car_physics.rotation.y = rotation.y

# NEW COLLISION DETECTION
# This function will be called when any physics body enters the pickup area
func _on_pickup_area_body_entered(body: Node) -> void:
	print("Body entered pickup area: ", body.name)
	
	# First check if the body is the ragdoll body of a passenger
	if body is RigidBody3D and body.get_parent() and body.get_parent().has_method("activate_ragdoll"):
		var passenger = body.get_parent()
		print("Passenger detected: ", passenger.name)
		
		# Only activate if the passenger is not already picked up or delivered
		if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
			print("Activating passenger ragdoll")
			passenger.activate_ragdoll(self, current_direction)
			emit_signal("passenger_hit", passenger)
			
			# Directly call the level manager's reset function
			var level_manager = get_node("/root/Main/LevelManager")
			if level_manager and level_manager.has_method("schedule_level_reset"):
				level_manager.schedule_level_reset(passenger)
