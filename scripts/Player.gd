extends Node3D

# Grid positions and level data
var grid_position: Vector2i = Vector2i(0, 0)
var grid_width: int
var grid_height: int
var cell_size: float
var tile_data: Array = []  # 2D array of blueprint chars
var door_map: Dictionary = {}  # (x,y) -> door node
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)

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

func _ready() -> void:
	# You might look up a LevelManager if desired:
	var level_manager = get_node("/root/Main/LevelManager") if has_node("/root/Main/LevelManager") else null
	if level_manager == null:
		push_error("No LevelManager found at /root/Main/LevelManager")
	update_world_position()
	update_model_rotation()

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
	
	# If it's a door, read the door node's properties
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

# Function to turn the car left (counter-clockwise)
func turn_left() -> void:
	if is_moving or is_turning:
		return
		
	# Update direction (subtract 1 with wrap-around)
	current_direction = (current_direction - 1 + 4) % 4
	start_turn_animation()
	print("Turned left: now facing " + Direction.keys()[current_direction])

# Function to turn the car right (clockwise)
func turn_right() -> void:
	if is_moving or is_turning:
		return
		
	# Update direction (add 1 with wrap-around)
	current_direction = (current_direction + 1) % 4
	start_turn_animation()
	print("Turned right: now facing " + Direction.keys()[current_direction])

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
