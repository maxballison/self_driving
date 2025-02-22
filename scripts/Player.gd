extends Node3D

var grid_position: Vector2i = Vector2i(0, 0)

# We’ll store references to current level data here.
var grid_width: int
var grid_height: int
var cell_size: float

func _ready() -> void:
	# Optionally, find and store the LevelManager at runtime:
	var level_manager = get_node("/root/Main/LevelManager")  # Adjust the path if needed
	if level_manager:
		# Get the grid data from the manager.
		grid_width = level_manager.current_level_width
		grid_height = level_manager.current_level_height
		cell_size = level_manager.cell_size

		update_world_position()
	else:
		push_error("LevelManager not found in scene!")

func move(direction: String) -> void:
	var new_pos = grid_position
	match direction:
		"North":
			new_pos.y -= 1
		"South":
			new_pos.y += 1
		"East":
			new_pos.x += 1
		"West":
			new_pos.x -= 1
		_:
			return  # Do nothing on invalid direction

	# Check boundaries with our local grid dimensions
	if new_pos.x < 0 or new_pos.x >= grid_width or new_pos.y < 0 or new_pos.y >= grid_height:
		print("Movement blocked: out of bounds")
		return

	# If inside bounds, finalize the move.
	grid_position = new_pos
	update_world_position()

func update_world_position() -> void:
	position = Vector3(
		float(grid_position.x) * cell_size,
		1.0,  # keep player above the ground a bit
		float(grid_position.y) * cell_size
	)
	print("Player moved to grid coord:", grid_position)
