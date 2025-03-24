extends Camera3D

# Camera properties
@export var min_distance: float = 18.0  # Minimum distance from level center
@export var height_multiplier: float = 0.85  # Height relative to distance
@export var angle_degrees: float = 40.0  # Camera angle in degrees
@export var padding: float = 5.0  # Extra padding around level bounds

func _ready() -> void:
	# Ensure camera is properly positioned on game start
	call_deferred("adjust_camera")

func _on_level_manager_level_switched() -> void:
	adjust_camera()

func adjust_camera():
	var level_manager = get_node_or_null("/root/Main/LevelManager")
	if level_manager:
		var w = level_manager.current_level_width
		var h = level_manager.current_level_height
		var size = level_manager.cell_size
		
		# Calculate level dimensions
		var level_width = float(w) * size
		var level_height = float(h) * size
		
		# Calculate level center
		var center_x = level_width * 0.5
		var center_z = level_height * 0.5
		
		# Calculate required distance based on level size
		# Use the larger dimension to ensure the entire level is visible
		var required_distance = max(level_width, level_height) * 0.7 + padding
		var camera_distance = max(required_distance, min_distance)
		
		# Calculate camera height based on distance
		var camera_height = camera_distance * height_multiplier
		
		# Convert angle to radians
		var angle_rad = deg_to_rad(angle_degrees)
		
		# Calculate camera position using spherical coordinates
		var offset_z = camera_distance * cos(angle_rad)
		var offset_y = camera_distance * sin(angle_rad)
		
		# Set camera position and target
		position = Vector3(center_x, offset_y, center_z + offset_z)
		look_at(Vector3(center_x, 0.0, center_z), Vector3.UP)
		
		print("Camera adjusted for level: ", w, "x", h, " at distance: ", camera_distance)
	else:
		push_error("LevelManager not found!")
