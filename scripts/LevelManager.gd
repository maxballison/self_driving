extends Node3D

var current_level_instance: Node3D = null
var current_level_width: int = 10
var current_level_height: int = 10
var cell_size: float = 1.0

signal level_switched()

func _ready() -> void:
	load_level("res://GeneratedLevels/level_1.tscn")

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

	# Read the level's properties
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

	# If the scene has tile_data and door_map, we can pass them to the player
	var tile_data_array: Array = []
	var door_map: Dictionary = {}
	var passenger_map: Dictionary = {}
	var destination_map: Dictionary = {}
	
	# Initialize and populate data from level
	if current_level_instance.has_method("populate_tile_data_and_entities"):
		current_level_instance.populate_tile_data_and_entities()
	
	if current_level_instance.get("tile_data"):
		tile_data_array = current_level_instance.tile_data
	if current_level_instance.get("door_map"):
		door_map = current_level_instance.door_map
	if current_level_instance.get("passenger_map"):
		passenger_map = current_level_instance.passenger_map
	if current_level_instance.get("destination_map"):
		destination_map = current_level_instance.destination_map
		
	# Reset passenger states
	for pos in passenger_map:
		var passenger = passenger_map[pos]
		if passenger.has_method("reset_state"):
			passenger.reset_state()

	# Now set up the Player
	var player = get_node("/root/Main/Player")
	if player:
		# Use provided spawn_position if set, otherwise use level's start_position
		if spawn_position.x >= 0 and spawn_position.y >= 0:
			player.grid_position = spawn_position
		else:
			player.grid_position = level_start_pos
		
		# Set player direction to level's start_direction
		player.current_direction = level_start_dir
		
		player.grid_width = current_level_width
		player.grid_height = current_level_height
		player.cell_size = cell_size
		player.tile_data = tile_data_array
		player.door_map = door_map
		player.passenger_map = passenger_map
		player.destination_map = destination_map
		
		# Clear any existing passengers in car
		if player.has_method("clear_passengers"):
			player.clear_passengers()
		player.should_teleport = true
		player.update_world_position()
		
		# Connect signals if not already connected
		_connect_player_signals(player)
		
		# Call refresh_nearby_passengers after everything is set up
		player.refresh_nearby_passengers()
	
	# For debugging, print the maps
	print("Level loaded with:")
	print("- Tiles: ", tile_data_array.size(), " rows")
	print("- Doors: ", door_map.size())
	print("- Passengers: ", passenger_map.size())
	print("- Destinations: ", destination_map.size())
	
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
	# We're ignoring the next_level_spawn parameter (keeping it for backward compatibility)
	load_level(next_level_path)

func _on_passenger_hit(passenger) -> void:
	print("Passenger hit by car, restarting level after delay...")
	# This function is now primarily for signal response logging
	# The actual reset is handled by schedule_level_reset

# This is the primary way to reset the level, called from multiple places
func schedule_level_reset(passenger = null) -> void:
	print("Level reset scheduled after passenger hit!")
	
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
			# Use a negative spawn position to indicate we should use the level's start position
			load_level(current_path)
	)

func _on_level_completed() -> void:
	print("Level completed signal received!")
	# You can add special handling for level completion here
	
	# Get next level information from the level itself
	if current_level_instance:
		var next_level = current_level_instance.next_level_path
		
		# If next_level_path is empty, try to find it from a door
		if next_level == "":
			# Find a door to use for next level info as a fallback
			for door_pos in current_level_instance.door_map:
				var door = current_level_instance.door_map[door_pos]
				if door.has_method("get"):
					next_level = door.get("next_level_path")
					break
		
		# Go to next level after a delay if we have a path
		if next_level != "":
			print("Transitioning to next level after delay: ", next_level)
			
			# Create a transition effect (e.g., fade or message)
			# For simplicity, we'll just use a timer
			var transition_delay = current_level_instance.transition_delay
			if transition_delay <= 0:
				transition_delay = 2.0 # Default delay
				
			var timer = get_tree().create_timer(transition_delay)
			timer.timeout.connect(func():
				load_level(next_level)
			)
