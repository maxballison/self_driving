extends Node3D

@export var grid_width: int = 10
@export var grid_height: int = 10
@export var cell_size: float = 1.0

# Add exported variables for the next level
@export var next_level_path: String = ""
@export var transition_delay: float = 2.0  # Seconds to wait before transitioning

# New variables for level start position and direction
@export var start_position: Vector2i = Vector2i(1, 1)
@export var start_direction: int = 1  # Default: East (Direction.EAST in Player.gd)

# This will store the "blueprint" characters for each cell.
@export var tile_data: Array = []

# This will store door nodes keyed by their grid positions.
@export var door_map: Dictionary = {}

# New maps for passenger and destination nodes
@export var passenger_map: Dictionary = {}
@export var destination_map: Dictionary = {}

func _ready() -> void:
	populate_tile_data_and_entities()
	place_floor_tiles()
	

func populate_tile_data_and_entities() -> void:
	# Initialize tile_data as a 2D array matching grid_width and grid_height
	tile_data.clear()
	tile_data.resize(grid_height)
	for y in range(grid_height):
		tile_data[y] = []
		tile_data[y].resize(grid_width)
		# Fill with some default blueprint character, if desired
		for x in range(grid_width):
			tile_data[y][x] = " "  # Default to empty space

	# Clear any existing entries in maps
	door_map.clear()
	passenger_map.clear()
	destination_map.clear()

	# Loop through child nodes
	for child in get_children():
		# Skip floor tiles
		if "TileFloor" in child.name:
			continue
			
		# We'll calculate the approximate grid position based on the child's transform.origin.
		# Ensure your scene's XZ-plane matches how your grid is laid out.
		var child_pos: Vector3 = child.transform.origin

		# Convert to grid coordinates
		var grid_x: int = int(round(child_pos.x / cell_size))
		var grid_y: int = int(round(child_pos.z / cell_size))
		var grid_pos = Vector2i(grid_x, grid_y)

		# Make sure the coordinate is within the grid bounds
		if grid_x < 0 or grid_x >= grid_width:
			continue
		if grid_y < 0 or grid_y >= grid_height:
			continue

		# Categorize the child based on its type/name
		if "Door" in child.name:
			door_map[grid_pos] = child
			tile_data[grid_y][grid_x] = "d"  # Mark the blueprint char for a door
		elif "Wall" in child.name:
			tile_data[grid_y][grid_x] = "#"
		elif "Passenger" in child.name:
			passenger_map[grid_pos] = child
			tile_data[grid_y][grid_x] = "p"  # Mark as passenger
		elif "Destination" in child.name:
			destination_map[grid_pos] = child
			tile_data[grid_y][grid_x] = "D"  # Mark as destination
		else:
			# Otherwise, store some other blueprint character or logic.
			tile_data[grid_y][grid_x] = " "

	# At this point, tile_data has your blueprint characters, and entity maps hold the actual nodes
	print("Level initialized with:")
	print("- ", door_map.size(), " doors")
	print("- ", passenger_map.size(), " passengers")
	print("- ", destination_map.size(), " destinations")
	
func place_floor_tiles() -> void:
	# Create a floor under the entire level
	var floor_scene = preload("res://tiles/TileFloor.tscn")
	
	if floor_scene:
		for x in range(grid_width):
			for y in range(grid_height):
				var floor_instance = floor_scene.instantiate()
				floor_instance.name = "TileFloor_" + str(x) + "_" + str(y)
				floor_instance.transform.origin = Vector3(float(x) * cell_size, -0.1, float(y) * cell_size)
				add_child(floor_instance)
