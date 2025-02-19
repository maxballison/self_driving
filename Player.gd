extends Node3D

# Current grid coordinates (x, y).
var grid_position: Vector2 = Vector2.ZERO

# Fetched from the parent Level in _ready().
var grid_size: Vector2
var cell_size: float
var x_offset: float
var z_offset: float

func _ready() -> void:
	var level = get_parent()
	if level:
		# Read the grid dimensions and cell size from the Level node.
		grid_size = Vector2(level.grid_width, level.grid_height)
		cell_size = level.cell_size

		# Calculate the same offsets used by Level.gd to center the Player properly.
		x_offset = (grid_size.x - 1) * cell_size / 2.0
		z_offset = (grid_size.y - 1) * cell_size / 2.0

		update_position()  # Ensure Player starts in the correct spot
	else:
		push_error("Parent Level node not found!")

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
			print("Invalid direction:", direction)
			return

	# Check boundaries.
	if new_pos.x < 0 or new_pos.x >= grid_size.x or new_pos.y < 0 or new_pos.y >= grid_size.y:
		print("Movement blocked: out of bounds")
		return

	# Update to the new valid position.
	grid_position = new_pos
	update_position()

func update_position() -> void:
	# Convert the grid_position to a world position, matching the grid’s center offset.
	position = Vector3(
		grid_position.x * cell_size - x_offset,
		1,  # Keep the player slightly above the ground.
		grid_position.y * cell_size - z_offset
	)
	print("Player moved to:", grid_position)
