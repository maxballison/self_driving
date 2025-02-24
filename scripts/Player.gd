extends Node3D

var grid_position: Vector2i = Vector2i(0, 0)
var grid_width: int
var grid_height: int
var cell_size: float

var tile_data: Array = []  # 2D array of blueprint chars
var door_map: Dictionary = {}  # (x,y) -> door node

signal door_entered(next_level_path: String, next_level_spawn: Vector2i)

func _ready() -> void:
	# You might look up a LevelManager if desired:
	var level_manager = get_node("/root/Main/LevelManager") if has_node("/root/Main/LevelManager") else null
	if level_manager == null:
		push_error("No LevelManager found at /root/Main/LevelManager")
	update_world_position()


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
			return

	# Check boundaries
	if new_pos.x < 0 or new_pos.x >= grid_width or new_pos.y < 0 or new_pos.y >= grid_height:
		print("Blocked: out of bounds")
		return

	# Check tile_data for walls
	var tile_char = tile_data[new_pos.y][new_pos.x]  # e.g. ' ', '#', 'd'
	if tile_char == '#' or tile_char == 'x':
		print("Blocked: wall present")
		return

	grid_position = new_pos
	
	# If it's a door, read the door node's properties
	if tile_char == 'd':
		var door_node = door_map.get(new_pos, null)
		if door_node:
			if door_node.has_method("get"):
				# Attempt to read the door script's exports
				var next_level = door_node.get("next_level_path")
				var spawn_pos: Vector2i = door_node.get("next_level_spawn")
				print("Stepped on a door at ", new_pos, ". Next level: ", next_level)
				emit_signal("door_entered", next_level, spawn_pos)
				grid_position = spawn_pos
			else:
				print("Door node found, but missing door script. No next_level data.")

	# Finalize the move
	update_world_position()

func update_world_position() -> void:
	position = Vector3(
		float(grid_position.x) * cell_size,
		1.0,
		float(grid_position.y) * cell_size
	)
	print("Player moved to grid coord:", grid_position)
