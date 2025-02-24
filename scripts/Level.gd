extends Node3D

@export var grid_width: int = 10
@export var grid_height: int = 10
@export var cell_size: float = 1.0

# This will store the "blueprint" characters for each cell.
@export var tile_data: Array = []

# This will store door nodes keyed by their grid positions.
@export var door_map: Dictionary = {}

func _ready() -> void:
	populate_tile_data_and_doors()

func populate_tile_data_and_doors() -> void:
	# Initialize tile_data as a 2D array matching grid_width and grid_height
	tile_data.clear()
	tile_data.resize(grid_height)
	for y in range(grid_height):
		tile_data[y] = []
		tile_data[y].resize(grid_width)
		# Fill with some default blueprint character, if desired
		for x in range(grid_width):
			tile_data[y][x] = "."

	# Clear any existing entries in door_map
	door_map.clear()

	# Loop through child nodes
	for child in get_children():
		# We'll calculate the approximate grid position based on the child's transform.origin.
		# Ensure your scene's XZ-plane matches how your grid is laid out.
		var child_pos: Vector3 = child.transform.origin

		# Convert to grid coordinates
		var grid_x: int = int(round(child_pos.x / cell_size))
		var grid_y: int = int(round(child_pos.z / cell_size))

		# Make sure the coordinate is within the grid bounds
		if grid_x < 0 or grid_x >= grid_width:
			continue
		if grid_y < 0 or grid_y >= grid_height:
			continue

		# Decide if this child is a "door" or a normal tile.
		# For example, if door nodes have "Door" in their name:
		if "door" in child.name.to_lower():
			door_map[Vector2i(grid_x, grid_y)] = child
			tile_data[grid_y][grid_x] = "d"  # Mark the blueprint char for a door
		elif "wall" in child.name.to_lower():
			tile_data[grid_y][grid_x] = "#"
		else:
			# Otherwise, store some other blueprint character or logic.
			tile_data[grid_y][grid_x] = " "

	# At this point, tile_data has your blueprint characters, and door_map holds door nodes
