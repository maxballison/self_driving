extends Camera3D

func _ready() -> void:
	# You may need to ensure that LevelManager has valid data by this time.
	# One way is to confirm that LevelManager is ordered above the Camera in the scene tree
	# or that the level is already loaded. Otherwise, you can do call_deferred() or a signal.
	var level_manager = get_node("/root/Main/LevelManager")
	if level_manager:
		var w = level_manager.current_level_width
		var h = level_manager.current_level_height
		var size = level_manager.cell_size

		# If your level is NOT already centered in the scene:
		#   The center of the grid is roughly at ( (w-1)*0.5, 0, (h-1)*0.5 ) * cell_size.
		var center_x = (float(w) - 1.0) * 0.5 * size
		var center_z = (float(h) - 1.0) * 0.5 * size

		# Place the camera at some offset above and maybe a bit "south" (z + 4)
		position = Vector3(center_x, 9.0, center_z + 5.0)

		# If you also want the camera to look downward at the level’s center:
		look_at(Vector3(center_x, 0.0, center_z), Vector3.UP)
	else:
		push_error("LevelManager not found!")
