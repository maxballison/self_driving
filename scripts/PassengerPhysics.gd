extends Node3D

@export var destination_id: int = 0
@export var passenger_name: String = "Passenger"

# Direction enum for compatibility with player
enum Direction { NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3 }

# State tracking
var is_picked_up: bool = false
var is_delivered: bool = false
var is_ragdolling: bool = false

# Visual nodes
@onready var visual_model = $VisualModel
@onready var destination_indicator = $DestinationIndicator
@onready var ragdoll_body = $RagdollBody if has_node("RagdollBody") else null

# Car reference when picked up
var car_ref: Node3D = null

# Signals
signal picked_up(passenger)
signal delivered(passenger)
signal hit_by_car(passenger)

func _ready():
	# Set color for destination indicator
	set_destination_color()
	
	# Make sure the rigid body starts in a clean state
	if ragdoll_body:
		ragdoll_body.freeze = true

func _process(delta):
	# Update indicator position when picked up
	if is_picked_up and car_ref and destination_indicator:
		update_indicator_position()

func set_destination_color():
	# Set indicator color based on destination_id
	var colors = [
		Color(1, 0, 0),    # Red
		Color(0, 1, 0),    # Green
		Color(0, 0, 1),    # Blue
		Color(1, 1, 0),    # Yellow
		Color(1, 0, 1),    # Magenta
		Color(0, 1, 1),    # Cyan
		Color(1, 0.5, 0),  # Orange
		Color(0.5, 0, 1)   # Purple
	]
	
	var color_index = destination_id % colors.size()
	var color = colors[color_index]
	
	# Create new material with emission
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	
	# Apply the material
	if destination_indicator:
		destination_indicator.material_override = material

func pick_up(car: Node3D) -> bool:
	if is_picked_up or is_delivered or is_ragdolling:
		return false
	
	# Store reference to car
	car_ref = car
	is_picked_up = true
	
	# Hide the visual model
	if visual_model:
		visual_model.visible = false
	
	emit_signal("picked_up", self)
	return true

func deliver() -> bool:
	if not is_picked_up or is_delivered or is_ragdolling:
		return false
	
	is_picked_up = false
	is_delivered = true
	car_ref = null
	
	# Hide everything
	if visual_model:
		visual_model.visible = false
	
	if destination_indicator:
		destination_indicator.visible = false
	
	emit_signal("delivered", self)
	return true

# This is called directly by the car when a collision is detected
func activate_ragdoll(car = null, car_direction: int = -1):
	print("PASSENGER: Activating ragdoll physics! Car direction: ", car_direction)
	
	if is_ragdolling or is_picked_up or is_delivered:
		return
	
	is_ragdolling = true
	car_ref = car
	
	# Hide normal model
	if visual_model:
		visual_model.visible = false
	
	# IMPORTANT: Make sure the ragdoll model is immediately displayed
	# and positioned correctly
	if ragdoll_body:
		ragdoll_body.visible = true
		
		# Calculate a force vector opposite to the car's movement direction
		# but with a significant upward component
		var impulse = Vector3(0, 5, 0)  # Default up
		
		if car_direction != -1:
			match car_direction:
				Direction.NORTH:  # Car coming from south, throw passenger north
					impulse = Vector3(0, 5, -15)
				Direction.SOUTH:  # Car coming from north, throw passenger south
					impulse = Vector3(0, 5, 15)
				Direction.EAST:   # Car coming from west, throw passenger east
					impulse = Vector3(15, 5, 0)
				Direction.WEST:   # Car coming from east, throw passenger west
					impulse = Vector3(-15, 5, 0)
		
		# Unfreeze physics immediately
		ragdoll_body.freeze = false
		
		# Apply forces immediately instead of with a delay
		ragdoll_body.apply_impulse(impulse)
		
		# Add random torque for tumbling
		var random_torque = Vector3(
			randf_range(-1, 1),
			randf_range(-1, 1),
			randf_range(-1, 1)
		).normalized() * 15.0
		
		ragdoll_body.apply_torque(random_torque)
		
		# Make sure we emit the signal
		print("Passenger emitting hit_by_car signal")
		emit_signal("hit_by_car", self)

func update_indicator_position():
	if not is_picked_up or not car_ref:
		return
		
	# Check if we need to reparent the indicator
	if destination_indicator.get_parent() == self:
		# First appearance above car - maintain world position
		var global_pos = destination_indicator.global_position
		remove_child(destination_indicator)
		get_tree().root.add_child(destination_indicator)
		destination_indicator.global_position = global_pos
	
	# Stack indicators when multiple passengers are in car
	var car_passengers = car_ref.current_passengers
	var passenger_index = car_passengers.find(self)
	
	if passenger_index >= 0:
		# Position above car with spacing based on index
		destination_indicator.global_position = car_ref.global_position + Vector3(0, 1.0 + (passenger_index * 0.3), 0)
