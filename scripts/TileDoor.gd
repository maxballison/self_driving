extends Node3D

@export var next_level_path: String = "res://GeneratedLevels/level_2.tscn"
@export var next_level_spawn: Vector2i = Vector2i(0, 0)

# Reference to the collision area
var door_area: Area3D = null

func _ready() -> void:
	# Set up door detection area if it doesn't exist already
	setup_door_area()
	# Add to doors group for tracking
	add_to_group("doors")

# Helper function to identify this as a door in collision detection
func is_door() -> bool:
	return true

# Set up the collision area for the door
func setup_door_area() -> void:
	# Check if we already have an Area3D node
	if has_node("DoorArea"):
		door_area = get_node("DoorArea")
	else:
		# Create a new Area3D for collision detection
		door_area = Area3D.new()
		door_area.name = "DoorArea"
		door_area.collision_layer = 16  # Layer 5 for doors
		door_area.collision_mask = 4    # Layer 3 for player
		add_child(door_area)
		
		# Add collision shape to the area
		var collision = CollisionShape3D.new()
		collision.name = "CollisionShape"
		
		# Create a box shape that covers the door
		var shape = BoxShape3D.new()
		shape.size = Vector3(0.9, 0.5, 0.9)  # Slightly smaller than a full tile
		collision.shape = shape
		
		# Position the collision shape
		collision.position = Vector3(0, 0.25, 0)  # Raise it slightly above ground
		
		door_area.add_child(collision)
		
		print("Created door collision area for: ", name)
	
	# Make sure we detect the player
	if door_area and not door_area.is_connected("body_entered", Callable(self, "_on_door_area_body_entered")):
		door_area.body_entered.connect(_on_door_area_body_entered)

# Called when a body enters the door's collision area
func _on_door_area_body_entered(body: Node) -> void:
	print("Body entered door area: ", body.name)
	
	# Check if this is the player
	if body.name == "Player":
		print("Player entered door at: ", global_position)
		
		# Emit signal via the player to trigger level transition
		if body.has_method("emit_signal"):
			print("Transitioning to: ", next_level_path, " spawn: ", next_level_spawn)
			body.emit_signal("door_entered", next_level_path, next_level_spawn)
