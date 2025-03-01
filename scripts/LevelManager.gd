extends Node3D

var current_level_instance: Node3D = null
var current_level_width: int
var current_level_height: int
var cell_size: float

signal level_switched()

func _ready() -> void:
	load_level("res://GeneratedLevels/level_1.tscn", Vector2i(1, 1))  # Example spawn

func load_level(scene_path: String, spawn_position: Vector2i) -> void:
	# Clean up existing level
	if current_level_instance:
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
	
	if current_level_instance.get("tile_data"):
		tile_data_array = current_level_instance.tile_data
	if current_level_instance.get("door_map"):
		door_map = current_level_instance.door_map

	# Now set up the Player
	var player = get_node("/root/Main/Player")  # Adjust if needed
	if player:
		player.grid_position = spawn_position
		player.grid_width    = current_level_width
		player.grid_height   = current_level_height
		player.cell_size     = cell_size
		player.tile_data     = tile_data_array
		player.door_map      = door_map
		player.update_world_position()

		# Connect the Player's door_entered signal if not already connected
		if not player.is_connected("door_entered", Callable(self, "_on_player_door_entered")):
				player.connect("door_entered", Callable(self, "_on_player_door_entered"))
	emit_signal("level_switched")

func switch_level(new_scene_path: String, entrance_door_position: Vector2i) -> void:
	# A helper to switch from the current level to the new one
	print("SWITCHING to", new_scene_path)
	load_level(new_scene_path, entrance_door_position)

func _on_player_door_entered(next_level_path: String, next_level_spawn: Vector2i) -> void:
	# Called when the player steps onto a door
	switch_level(next_level_path, next_level_spawn)
