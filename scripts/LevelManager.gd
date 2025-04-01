extends Node3D

var current_level_instance: Node3D = null
var current_level_width: int = 10
var current_level_height: int = 10
var cell_size: float = 1.0

signal level_switched()

func _ready() -> void:
	load_level("res://GeneratedLevels/level_2.tscn")

func load_level(scene_path: String, spawn_position: Vector2i = Vector2i(-1, -1)) -> void:
	print("Loading level: ", scene_path)
	
	# Clean up existing level
	if current_level_instance:
		# Find and clean up any orphaned indicators in the scene root
		for child in get_tree().root.get_children():
			if child is MeshInstance3D and "destination_indicator" in child.name.to_lower():
				child.queue_free()
				print("Cleaned up orphaned indicator")
		
		current_level_instance.queue_free()
		current_level_instance = null

	var scene_res = load(scene_path)
	if scene_res == null:
		push_error("Could not load level scene: " + scene_path)
		return

	# Instantiate and add
	current_level_instance = scene_res.instantiate()
	add_child(current_level_instance)

	# Read the level's properties for level boundaries
	if current_level_instance.get("grid_width"):
		current_level_width = current_level_instance.grid_width
		current_level_height = current_level_instance.grid_height
		cell_size = current_level_instance.cell_size
	else:
		current_level_width = 10
		current_level_height = 10
		cell_size = 1.0

	# Get the level's start position and direction
	var level_start_pos = Vector2i(1, 1)  # Default
	var level_start_dir = 1  # Default: East
	
	if current_level_instance.get("start_position"):
		level_start_pos = current_level_instance.start_position
	
	if current_level_instance.get("start_direction"):
		level_start_dir = current_level_instance.start_direction

	# Reset passenger states (now done differently due to physics-based system)
	var passengers = get_tree().get_nodes_in_group("passengers")
	for passenger in passengers:
		if passenger.has_method("reset_state"):
			passenger.reset_state()

	# Set up the Player with the new physics-based approach
	var player = get_node("/root/Main/Player")
	if player:
		# Calculate world position from grid position
		var world_position = Vector3(
			float(level_start_pos.x) * cell_size,
			0.2,  # Height offset for the car
			float(level_start_pos.y) * cell_size
		)
		
		# If spawn_position was provided, use it instead
		if spawn_position.x >= 0 and spawn_position.y >= 0:
			world_position = Vector3(
				float(spawn_position.x) * cell_size,
				0.2,
				float(spawn_position.y) * cell_size
			)
		
		# Set player position and rotation directly
		player.position = world_position
		
		# Calculate rotation from direction
		var rotation_y = 0.0
		match level_start_dir:
			0: rotation_y = 0.0        # North
			1: rotation_y = -PI * 0.5  # East
			2: rotation_y = -PI        # South
			3: rotation_y = -PI * 1.5  # West
		
		player.rotation.y = rotation_y
		
		# Ensure direction vector is updated from rotation
		if player.has_method("update_direction_from_rotation"):
			player.update_direction_from_rotation()
		
		# Clear any existing passengers in car
		if player.has_method("clear_passengers"):
			player.clear_passengers()
		
		# Stop any ongoing movement
		if player.has_method("stop"):
			player.stop()
		
		# Connect signals if not already connected
		_connect_player_signals(player)
	
	# Print debug info
	print("Level loaded: ", scene_path)
	print("Level dimensions: ", current_level_width, "x", current_level_height)
	print("Start position: ", level_start_pos)
	
	emit_signal("level_switched")

func _connect_player_signals(player: Node3D) -> void:
	# Connect all player signals we care about
	if not player.is_connected("door_entered", Callable(self, "_on_player_door_entered")):
		player.connect("door_entered", Callable(self, "_on_player_door_entered"))
		
	if not player.is_connected("passenger_hit", Callable(self, "_on_passenger_hit")):
		player.connect("passenger_hit", Callable(self, "_on_passenger_hit"))
		
	if not player.is_connected("level_completed", Callable(self, "_on_level_completed")):
		player.connect("level_completed", Callable(self, "_on_level_completed"))
	
	# Connect to script interpreter to stop execution when passenger hit
	var interpreter = get_node("/root/Main/ScriptInterpreter")
	if interpreter and not player.is_connected("passenger_hit", Callable(interpreter, "_on_passenger_hit")):
		player.connect("passenger_hit", Callable(interpreter, "_on_passenger_hit"))

func _on_player_door_entered(next_level_path: String, _unused_spawn: Vector2i) -> void:
	print("Door entered, switching to level: ", next_level_path)
	# Switch to the next level, using its own start position
	load_level(next_level_path)

func _on_passenger_hit(_passenger) -> void:
	print("Passenger hit by car, restarting level after delay...")
	# This function is now primarily for signal response logging
	# The actual reset is handled by schedule_level_reset

# This is the primary way to reset the level, called from multiple places
func schedule_level_reset(_passenger = null) -> void:
	print("Level reset scheduled!")
	
	# Check if a reset is already scheduled (to prevent multiple resets)
	if has_meta("reset_scheduled"):
		print("Reset already scheduled, ignoring additional requests")
		return
	
	# Mark that a reset is scheduled
	set_meta("reset_scheduled", true)
	
	# Stop code execution in the interpreter
	var interpreter = get_node("/root/Main/ScriptInterpreter")
	if interpreter:
		interpreter.is_running = false
	
	# Stop the player's movement
	var player = get_node("/root/Main/Player")
	if player and player.has_method("stop"):
		player.stop()
	
	# Clean up any orphaned indicators immediately
	for child in get_tree().root.get_children():
		if child is MeshInstance3D and (child.name.begins_with("DestinationIndicator") or "destination_indicator" in child.name.to_lower()):
			child.queue_free()
			print("Cleaned up orphaned indicator during reset")
	
	# Reset the level after a delay to show the ragdoll effect
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		# Clear the reset flag
		remove_meta("reset_scheduled")
		
		# Reload the current level
		if current_level_instance:
			var current_path = current_level_instance.scene_file_path
			print("Reloading level: ", current_path)
			load_level(current_path)
	)

func _on_level_completed() -> void:
	print("Level completed signal received!")
	
	# Get next level information from the level itself
	if current_level_instance:
		var next_level = ""
		
		# Get next level path if it exists
		if current_level_instance.has_method("get") and current_level_instance.get("next_level_path") != "":
			next_level = current_level_instance.next_level_path
		
		# If next_level_path is still empty, try to find it from a door
		if next_level == "" and current_level_instance.has_method("get") and current_level_instance.get("door_map"):
			var door_map = current_level_instance.door_map
			for door_pos in door_map:
				var door = door_map[door_pos]
				if door.has_method("get"):
					next_level = door.get("next_level_path")
					break
		
		# Go to next level after a delay if we have a path
		if next_level != "":
			print("Transitioning to next level after delay: ", next_level)
			
			# Get transition delay if available
			var transition_delay = 2.0  # Default delay
			if current_level_instance.has_method("get") and current_level_instance.get("transition_delay") > 0:
				transition_delay = current_level_instance.transition_delay
				
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				load_level(next_level)
			)
