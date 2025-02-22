@tool
extends EditorScript

@export var blueprint_file_path: String = "res://blueprints/blueprint1.txt"
@export var output_scene_path: String = "res://GeneratedLevels/level_1.tscn"

# A dictionary mapping characters to the tile scene paths
var tile_mapping := {
	' ': "res://tiles/TileEmpty.tscn",  # treat space as a floor
	'#': "res://tiles/TileEmpty.tscn",
	'x': "res://tiles/TileWall.tscn",
	'e': "res://tiles/Enemy.tscn",
	'd': "res://tiles/TileDoor.tscn",
}

func _run() -> void:
	# Called when you press the "Run" button in the script panel
	generate_level_from_blueprint(blueprint_file_path, output_scene_path)

func generate_level_from_blueprint(source_file: String, target_scene: String) -> void:
	if not FileAccess.file_exists(source_file):
		push_error("Blueprint file not found: " + source_file)
		return

	# Read the blueprint text
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Could not open blueprint file: " + source_file)
		return

	var blueprint_text = file.get_as_text()
	file.close()

	var lines = blueprint_text.split("\n", false)
	var root_node = Node3D.new()
	root_node.name = "GeneratedLevel"

	# We’ll track the width/height for the final scene
	var max_width: int = 0
	var max_height: int = lines.size()

	# Instantiate child tiles for each character
	for y in range(lines.size()):
		var line = lines[y]
		var chars = line.split("", false)  # split by each character
		if chars.size() > max_width:
			max_width = chars.size()

		for x in range(chars.size()):
			var c = chars[x]
			if tile_mapping.has(c):
				var scene_path = tile_mapping[c]
				if scene_path != "":
					var tile_scene = load(scene_path)
					if tile_scene:
						var tile_instance = tile_scene.instantiate()
						# Position the tile in 3D space 
						tile_instance.position = Vector3(
							float(x),
							0.0,
							float(y)
						)
						root_node.add_child(tile_instance)
						tile_instance.owner = root_node
			# else: ignore unknown characters or handle them as needed

	# Attach a Level.gd script to the generated root so it has the standard fields
	var level_script = preload("res://scripts/Level.gd")
	root_node.set_script(level_script)

	# Fill out the exported properties if you want them stored
	root_node.set("grid_width", max_width)
	root_node.set("grid_height", max_height)
	root_node.set("cell_size", 1.0) # or any default you want
	

	# Pack and save the new scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(root_node)
	var error = ResourceSaver.save(packed_scene, target_scene)
	if error == OK:
		print("Level generated and saved to: " + target_scene)
	else:
		push_error("Error saving scene: " + str(error))
