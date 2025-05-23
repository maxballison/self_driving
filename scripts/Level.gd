extends Node3D

@export var grid_width: int = 10
@export var grid_height: int = 10
@export var cell_size: float = 1.0

# Add these export variables to Level.gd
@export var generate_unified_collision: bool = true
@export var show_collision_debug: bool = false
@export var debug_color: Color = Color(0.0, 1.0, 0.0, 0.4)  # Semi-transparent green

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

	if generate_unified_collision:
		generate_floor_collision()



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
	

func generate_floor_collision() -> void:
	if not generate_unified_collision:
		print("Unified collision generation disabled.")
		return
		
	print("Generating unified floor collision...")
	
	# Clean up any existing collision and debug nodes
	var existing = get_node_or_null("UnifiedFloorCollision")
	if existing:
		existing.queue_free()
	
	var existing_debug = get_node_or_null("DebugContainer")
	if existing_debug:
		existing_debug.queue_free()
	
	# Create a new StaticBody3D for the floor collision
	var floor_body = StaticBody3D.new()
	floor_body.name = "UnifiedFloorCollision"
	floor_body.collision_layer = 1  # Layer 1 for environment
	floor_body.collision_mask = 7   # Layers 1+2+3 (environment, passengers, player)
	add_child(floor_body)
	
	# Create a debug container if needed
	var debug_container = null
	if show_collision_debug:
		debug_container = Node3D.new()
		debug_container.name = "DebugContainer"
		add_child(debug_container)
	
	# Find tile positions and calculate bounds
	var floor_tiles = []
	var min_x = INF
	var max_x = -INF
	var min_z = INF
	var max_z = -INF
	var fixed_y = 0
	var first_tile_found = false
	
	for child in get_children():
		# Skip objects that aren't floor tiles
		if not ("TileFloor" in child.name or "TileEmpty" in child.name):
			continue
			
		var pos = child.global_transform.origin
		floor_tiles.append(pos)
		
		# Track the bounds of the floor area
		min_x = min(min_x, pos.x - cell_size/2)
		max_x = max(max_x, pos.x + cell_size/2)
		min_z = min(min_z, pos.z - cell_size/2)
		max_z = max(max_z, pos.z + cell_size/2)
		
		# Get the Y position from the first tile
		if not first_tile_found:
			fixed_y = pos.y - 0.05  # Slightly below visible floor
			first_tile_found = true
	
	print("Found ", floor_tiles.size(), " floor tiles for collision")
	
	# If no floor tiles were found, exit early
	if floor_tiles.size() == 0:
		print("No floor tiles found. Collision generation aborted.")
		return
	
	# Create smaller box colliders for each tile instead of one big concave mesh
	for pos in floor_tiles:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(cell_size, 0.1, cell_size)  # Thin box for each tile
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(pos.x, fixed_y, pos.z)
		floor_body.add_child(collision_shape)
	
	print("Created floor collision with individual box shapes")
	
	# Create debug visualization if enabled
	if show_collision_debug and debug_container:
		for pos in floor_tiles:
			var debug_mesh = MeshInstance3D.new()
			debug_mesh.name = "DebugMesh_Tile"
			
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(cell_size, 0.1, cell_size)
			debug_mesh.mesh = box_mesh
			debug_mesh.position = Vector3(pos.x, fixed_y, pos.z)
			
			# Apply semi-transparent debug material
			var material = StandardMaterial3D.new()
			material.albedo_color = debug_color
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			debug_mesh.material_override = material
			
			debug_container.add_child(debug_mesh)
		
		print("Added debug visualization for floor collision")
# Create debug meshes for individual collision shapes
func create_tile_debug_mesh(position: Vector3, size: Vector3) -> MeshInstance3D:
	# Create a mesh instance for visualization
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DebugMesh_" + str(position.x) + "_" + str(position.z)
	
	# Create a box mesh with the same dimensions as the collision
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	debug_mesh.mesh = box_mesh
	
	# Create wireframe material
	var material = StandardMaterial3D.new()
	material.albedo_color = debug_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color.a = 0.4
	
	debug_mesh.material_override = material
	
	# Set the local position
	debug_mesh.position = position
	
	return debug_mesh
