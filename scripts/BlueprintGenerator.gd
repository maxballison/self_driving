@tool
extends EditorScript

@export var blueprint_file_path: String = "res://blueprints/blueprint4.txt"
@export var output_scene_path: String = "res://GeneratedLevels/level_4.tscn"

var tile_mapping := {
	'#': "res://tiles/TileWall.tscn",
	' ': "res://tiles/TileEmpty.tscn",
	'x': "res://tiles/TileWall.tscn",
	'e': "res://tiles/Enemy.tscn",
	'd': "res://tiles/TileDoor.tscn",
}

func _run() -> void:
	generate_level_from_blueprint(blueprint_file_path, output_scene_path)

func generate_level_from_blueprint(source_file: String, target_scene: String) -> void:
	if not FileAccess.file_exists(source_file):
		push_error("Blueprint file not found: " + source_file)
		return

	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Could not open blueprint file: " + source_file)
		return

	var blueprint_text = file.get_as_text()
	file.close()

	var lines = blueprint_text.split("\n", false)
	var root_node = Node3D.new()
	root_node.name = "GeneratedLevel"

	var max_width: int = 0
	var max_height: int = lines.size()
	var cell_size: float = 1.0  # Adjust if needed

	# Determine max_width by scanning all lines
	for line in lines:
		if line.length() > max_width:
			max_width = line.length()

	var half_width  = float(max_width - 1) * 0.5
	var half_height = float(max_height - 1) * 0.5

	var tile_counter = 0

	for y in range(lines.size()):
		var line = lines[y]
		for x in range(line.length()):
			var c = line[x]
			if tile_mapping.has(c):
				var scene_path = tile_mapping[c]
				if scene_path != "":
					var tile_scene = load(scene_path)  # a PackedScene
					if tile_scene:
						var tile_instance = tile_scene.instantiate()
						# Give the node a name that includes the scene’s filename plus a unique number
						var scene_name = scene_path.get_file().get_basename()  # e.g., "TileEmpty"
						tile_instance.name = scene_name + "_" + str(tile_counter)
						tile_counter += 1

						# Position the tile
						tile_instance.position = Vector3(
							float(x) * cell_size,
							0.0,
							float(y) * cell_size
						)

						root_node.add_child(tile_instance)
						tile_instance.owner = root_node

	# Attach the Level.gd script
	var level_script = preload("res://scripts/Level.gd")
	root_node.set_script(level_script)

	# Fill out the exported properties for the scene
	root_node.set("grid_width",  max_width)
	root_node.set("grid_height", max_height)
	root_node.set("cell_size",   cell_size)

	var packed_scene = PackedScene.new()
	packed_scene.pack(root_node)
	var err = ResourceSaver.save(packed_scene, target_scene)
	if err == OK:
		print("Level generated and saved to: " + target_scene)
	else:
		push_error("Error saving scene: " + str(err))
