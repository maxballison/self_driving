extends Node3D

var current_level_instance: Node3D = null
var current_level_width: int = 10
var current_level_height: int = 10
var cell_size: float = 1.0

signal level_switched()

func _ready() -> void:
	load_level("res://GeneratedLevels/level_1.tscn", Vector2i(1, 1))

func load_level(scene_path: String, spawn_position: Vector2i) -> void:
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
		player.grid_position = spawn_position
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

func _on_player_door_entered(next_level_path: String, next_level_spawn: Vector2i) -> void:
	print("Door entered, switching to level: ", next_level_path)
	# Switch to the next level
	load_level(next_level_path, next_level_spawn)

func _on_passenger_hit(passenger) -> void:
	print("Passenger hit by car, restarting level after delay...")
	# This function is now primarily for signal response logging
	# The actual reset is handled by schedule_level_reset

# This is the primary way to reset the level, called from multiple places
# This is the primary way to reset the level, called from multiple places
func schedule_level_reset(passenger = null) -> void:
	print("Level reset scheduled after passenger hit!")
	
	# Check if a reset is already scheduled (to prevent multiple resets)
	if has_meta("reset_scheduled"):
		print("Reset already scheduled, ignoring additional requests")
		return
	
	# Mark that a reset is scheduled
	set_meta("reset_scheduled", true)
	
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
			load_level(current_path, Vector2i(1, 1))
	)

func _on_level_completed() -> void:
	print("Level completed signal received!")
	# You can add special handling for level completion here
