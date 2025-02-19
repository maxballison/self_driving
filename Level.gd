extends Node3D

@export var grid_width: int = 10
@export var grid_height: int = 10

# Each grid cell is this many units apart in the X/Z plane.
@export var cell_size: float = 1.0

func _ready():
	var tile_scene = preload("res://Tile.tscn")

	# Calculate offsets so that the entire grid is centered at (0,0,0).
	var x_offset = (grid_width - 1) * cell_size / 2.0
	var z_offset = (grid_height - 1) * cell_size / 2.0

	# Create the grid of tiles.
	for x in range(grid_width):
		for y in range(grid_height):
			var tile = tile_scene.instantiate()
			tile.position = Vector3(
				x * cell_size - x_offset,
				0,
				y * cell_size - z_offset
			)
			add_child(tile)
