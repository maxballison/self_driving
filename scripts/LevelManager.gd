extends Node3D

var current_level_instance: Node3D = null
var current_level_width: int
var current_level_height: int
var cell_size: float

func _ready() -> void:
	# Optionally load the first level automatically:
	load_level("res://GeneratedLevels/level_1.tscn", Vector2i(0, 0))

func load_level(scene_path: String, spawn_position: Vector2i) -> void:
	# Clean up any existing level
	if current_level_instance:
		current_level_instance.queue_free()
		current_level_instance = null

	var scene_res = load(scene_path)
	if scene_res == null:
		push_error("Level scene could not be loaded: " + scene_path)
		return

	# Instantiate and add to the tree
	current_level_instance = scene_res.instantiate() 
	add_child(current_level_instance)

	# Read the level's properties
	if current_level_instance.has_method("grid_width"):
		current_level_width = current_level_instance.grid_width
		current_level_height = current_level_instance.grid_height
		cell_size = current_level_instance.cell_size
	else:
		# fallback or default
		current_level_width = 10
		current_level_height = 10
		cell_size = 1.0

	# Optionally tell the Player where to spawn
	var player = get_node("/root/Main/Player")  # Adjust if needed
	if player:
		player.grid_position = spawn_position
		player.grid_width = current_level_width
		player.grid_height = current_level_height
		player.cell_size = cell_size
		player.x_offset = (current_level_width - 1) * cell_size * 0.25
		player.z_offset = (current_level_height - 1) * cell_size * 0.25
		player.update_world_position()

func switch_level(new_scene_path: String, entrance_door_position: Vector2i):
	# A helper to switch from the current level to the new one
	load_level(new_scene_path, entrance_door_position)
