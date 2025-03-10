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
@onready var car_physics = $CarPhysics
@onready var pickup_area = $PassengerPickupArea

func _ready() -> void:
	# Set collision layer for car physics
	if car_physics:
		car_physics.collision_layer = 4  # Layer 3
		car_physics.collision_mask = 2   # Layer 2 (passengers)
	
	# Connect signals
	if car_physics:
		if not car_physics.is_connected("body_entered", Callable(self, "_on_car_physics_body_entered")):
			car_physics.connect("body_entered", Callable(self, "_on_car_physics_body_entered"))
	
	update_world_position()
	update_model_rotation()
	clear_passengers()

func clear_passengers() -> void:
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
func deliver() -> bool:
	if is_moving or is_turning:
		return false
	
	if current_passengers.size() == 0:
		print("No passengers in car to deliver!")
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
					if passenger.deliver():
						# Remove from current passengers array
						current_passengers.remove_at(i)
						
						# Remove from passenger_map (important to prevent collision after delivery)
						for map_pos in passenger_map.keys():
							if passenger_map[map_pos] == passenger:
								passenger_map.erase(map_pos)
								break
								
						destination.complete_delivery()
						print("Delivered passenger to destination ", destination.destination_id)
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
		
		# Find next level
		var next_level = ""
		var next_spawn = Vector2i(1, 1)
		
		# Find a door to use for next level info
		for door_pos in door_map:
			var door = door_map[door_pos]
			if door.has_method("get"):
				next_level = door.get("next_level_path")
				next_spawn = door.get("next_level_spawn")
				break
		
		# Go to next level if found
		if next_level != "":
			emit_signal("door_entered", next_level, next_spawn)

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

# Physics collision signals
func _on_car_physics_body_entered(body):
	# Check if the body belongs to a passenger
	if body.get_parent() and body.get_parent().has_method("activate_ragdoll"):
		var passenger = body.get_parent()
		print("Car hit passenger: ", passenger.name)
		
		# Directly activate the passenger's ragdoll mode
		if passenger.has_method("activate_ragdoll"):
			passenger.activate_ragdoll(self)
			
		# Signal that a passenger was hit
		emit_signal("passenger_hit", passenger)
