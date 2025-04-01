extends Node3D

# Physics-based movement variables
var is_driving: bool = false
var move_speed: float = 5.0  # Units per second
var is_turning: bool = false
var gravity_scale: float = 0.5  # Reduced gravity for floatier feel

# Direction vector (normalized)
var current_direction_vec: Vector3 = Vector3(1, 0, 0)  # Default: facing East

# Fall detection
var fall_threshold: float = -10.0  # Y position below which the car is considered fallen
var initial_y_position: float = 0.2 
var is_falling: bool = false
var last_on_floor: float = 0.0  # Time when last on floor

# Passenger tracking
var current_passengers: Array = []
var max_passengers: int = 3
var nearby_passengers: Array = []
var nearby_destinations: Array = []

# Track collision with walls
var wall_collision: bool = false

# Physics car body and components
@onready var car_physics = $CarPhysicsBody
@onready var pickup_area = $PassengerPickupArea

# Signals - keeping compatibility with existing connections
signal door_entered(next_level_path: String, next_level_spawn: Vector2i)
signal passenger_hit(passenger)
signal passenger_picked_up(passenger)
signal passenger_delivered(passenger, destination)
signal level_completed()

func _ready() -> void:
    # Set up the car physics body
    # We'll check if it's a RigidBody3D, if not, we need to modify the scene structure
    if car_physics and car_physics is RigidBody3D:
        # Set up RigidBody properties
        car_physics.gravity_scale = gravity_scale
        car_physics.collision_layer = 4  # Layer 3
        car_physics.collision_mask = 3   # Layers 1+2 (walls + passengers)
        car_physics.freeze = true  # Start frozen until we intentionally move
    else:
        print("WARNING: CarPhysicsBody should be a RigidBody3D")
    
    # Connect passenger pickup area signals
    if pickup_area:
        pickup_area.collision_mask = 2  # Layer 2 (passengers)
        pickup_area.monitoring = true
        
        # Connect signals for detecting entities
        if not pickup_area.is_connected("body_entered", Callable(self, "_on_pickup_area_body_entered")):
            pickup_area.connect("body_entered", Callable(self, "_on_pickup_area_body_entered"))
        
        if not pickup_area.is_connected("body_exited", Callable(self, "_on_pickup_area_body_exited")):
            pickup_area.connect("body_exited", Callable(self, "_on_pickup_area_body_exited"))
    
    # Initial position
    initial_y_position = position.y
    last_on_floor = Time.get_ticks_msec() / 1000.0
    
    # Set initial direction vector based on rotation
    update_direction_from_rotation()
    
    clear_passengers()

func _physics_process(delta: float) -> void:
    # Check if the car physics exists and is a RigidBody3D
    if car_physics and car_physics is RigidBody3D:
        # Check if there's a floor/road tile below us
        var ray_start = global_position
        var ray_end = ray_start + Vector3(0, -0.5, 0)  # Cast 0.5 unit down
        
        var space_state = get_world_3d().direct_space_state
        var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
        query.collision_mask = 1  # Layer 1 (environment)
        
        var result = space_state.intersect_ray(query)
        
        # Floor detection
        if not result.is_empty():
            # We're on a floor
            if is_falling:
                is_falling = false
                # If we were falling but found ground again, apply slight damping to movement
                if car_physics.linear_velocity.length() > 0.5:
                    car_physics.linear_velocity *= 0.9
            
            last_on_floor = Time.get_ticks_msec() / 1000.0
            
            # If we're driving and on a floor, maintain controlled movement
            if is_driving and not wall_collision and not is_turning:
                # Use physics for movement - apply a force instead of direct position manipulation
                car_physics.freeze = false
                car_physics.linear_velocity = current_direction_vec * move_speed
            elif not is_driving and not is_turning:
                # When not driving, apply damping to gradually stop
                if car_physics.linear_velocity.length() > 0.1:
                    car_physics.linear_velocity *= 0.9
                else:
                    car_physics.linear_velocity = Vector3.ZERO
                    if not is_falling:
                        car_physics.freeze = true
        else:
            # No floor detected, start falling with physics
            var current_time = Time.get_ticks_msec() / 1000.0
            if (current_time - last_on_floor) > 0.1:  # Small delay to prevent instant falling
                is_falling = true
                car_physics.freeze = false
                
                # Let gravity do its work
                # Apply a slight forward momentum when falling off an edge
                if is_driving:
                    car_physics.linear_velocity = current_direction_vec * move_speed * 0.5
    
    # Check for falling off the edge
    if position.y < fall_threshold:
        _handle_fall()
    
    # Reset wall collision flag for next frame
    wall_collision = false
    
    # Update position to match physics body
    if car_physics and car_physics is RigidBody3D:
        position = car_physics.position

func update_direction_from_rotation() -> void:
    # Calculate direction vector from rotation with correct Godot coordinate system
    # Forward (NORTH) is -Z, Right (EAST) is +X, etc.
    current_direction_vec = Vector3(0, 0, -1).rotated(Vector3.UP, rotation.y).normalized()
    print("Direction updated: ", current_direction_vec)
    
    # Update physics body rotation if it exists
    if car_physics:
        car_physics.rotation = rotation

# COMMAND FUNCTIONS

func drive() -> void:
    is_driving = true
    if car_physics and car_physics is RigidBody3D:
        car_physics.freeze = false
    print("Car started driving continuously")

func stop() -> void:
    is_driving = false
    # Don't freeze immediately, let physics slow it down naturally
    print("Car stopped")

func turn_left() -> void:
    if is_turning:
        return
        
    is_turning = true
    
    # Stop current movement during turn
    var prev_driving = is_driving
    is_driving = false
    
    # Turn exactly 90 degrees counter-clockwise (PI/2 radians)
    var target_rotation = rotation.y + PI/2
    var tween = create_tween()
    tween.tween_property(self, "rotation:y", target_rotation, 0.5)
    tween.tween_callback(func():
        is_turning = false
        update_direction_from_rotation()
        
        # Resume driving if we were driving before
        is_driving = prev_driving
    )
    
    print("Turning left by 90 degrees")

func turn_right() -> void:
    if is_turning:
        return
        
    is_turning = true
    
    # Stop current movement during turn
    var prev_driving = is_driving
    is_driving = false
    
    # Turn exactly 90 degrees clockwise (-PI/2 radians)
    var target_rotation = rotation.y - PI/2
    var tween = create_tween()
    tween.tween_property(self, "rotation:y", target_rotation, 0.5)
    tween.tween_callback(func():
        is_turning = false
        update_direction_from_rotation()
        
        # Resume driving if we were driving before
        is_driving = prev_driving
    )
    
    print("Turning right by 90 degrees")

func wait(seconds: float) -> void:
    # Create a timer to pause execution
    var prev_driving = is_driving
    is_driving = false
    print("Waiting for ", seconds, " seconds")
    
    var timer = get_tree().create_timer(seconds)
    await timer.timeout
    
    # Resume previous state if we were driving
    is_driving = prev_driving
    print("Wait complete, driving state: ", is_driving)

func pick_up() -> bool:
    if current_passengers.size() >= max_passengers:
        print("Car is full! Cannot pick up more passengers.")
        return false
    
    # Try to pick up nearby passengers
    if nearby_passengers.size() > 0:
        for passenger in nearby_passengers:
            if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
                if passenger.pick_up(self):
                    current_passengers.append(passenger)
                    print("Picked up passenger going to destination ", passenger.destination_id)
                    emit_signal("passenger_picked_up", passenger)
                    return true
    
    print("No passengers to pick up nearby!")
    return false

func drop_off() -> bool:
    if current_passengers.size() == 0:
        print("No passengers in car to drop off!")
        return false
    
    # Check for nearby destinations
    if nearby_destinations.size() > 0:
        for destination in nearby_destinations:
            # Find a passenger that matches this destination
            for i in range(current_passengers.size()):
                var passenger = current_passengers[i]
                if passenger.destination_id == destination.destination_id:
                    if passenger.deliver():
                        # Remove from current passengers array
                        current_passengers.remove_at(i)
                        
                        destination.complete_delivery()
                        print("Dropped off passenger at destination ", passenger.destination_id)
                        emit_signal("passenger_delivered", passenger, destination)
                        
                        # Check if all passengers have been delivered
                        check_level_completion()
                        return true
    
    print("No matching destination nearby for any passenger!")
    return false

# COLLISION HANDLING

func _on_pickup_area_body_entered(body: Node) -> void:
    print("Body entered pickup area: ", body.name)
    
    # Check if the body is a passenger's ragdoll
    if body is RigidBody3D and body.get_parent() and body.get_parent().has_method("activate_ragdoll"):
        var passenger = body.get_parent()
        print("Passenger detected: ", passenger.name)
        
        # Only activate if the passenger is not already picked up or delivered
        if not passenger.is_picked_up and not passenger.is_delivered and not passenger.is_ragdolling:
            print("Activating passenger ragdoll")
            passenger.activate_ragdoll(self, -1)  # -1 means use relative position for impulse
            emit_signal("passenger_hit", passenger)
            
            # Directly call the level manager's reset function
            var level_manager = get_node("/root/Main/LevelManager")
            if level_manager and level_manager.has_method("schedule_level_reset"):
                level_manager.schedule_level_reset(passenger)
    elif body.get_parent() and body.get_parent().has_method("is_passenger"):
        # If this is a passenger, add it to nearby passengers
        nearby_passengers.append(body.get_parent())
    elif body.get_parent() and body.get_parent().has_method("is_destination"):
        # If this is a destination, add it to nearby destinations
        nearby_destinations.append(body.get_parent())
    elif body is StaticBody3D or "Wall" in body.name:
        # Handle collision with walls
        wall_collision = true
        stop()
        print("Wall collision detected, stopping car")
    elif (body is StaticBody3D and "Floor" in body.name) or body.is_in_group("floor"):
        # We're on a floor tile, reset falling state
        is_falling = false
        last_on_floor = Time.get_ticks_msec() / 1000.0

func _on_pickup_area_body_exited(body: Node) -> void:
    # Remove destinations/passengers from the nearby lists when they exit
    if body.get_parent() and body.get_parent().has_method("is_passenger"):
        var idx = nearby_passengers.find(body.get_parent())
        if idx != -1:
            nearby_passengers.remove_at(idx)
    elif body.get_parent() and body.get_parent().has_method("is_destination"):
        var idx = nearby_destinations.find(body.get_parent())
        if idx != -1:
            nearby_destinations.remove_at(idx)
    elif (body is StaticBody3D and "Floor" in body.name) or body.is_in_group("floor"):
        # We've left a floor tile - start a short timer before considering falling
        var current_time = Time.get_ticks_msec() / 1000.0
        last_on_floor = current_time  # We'll check against this time before enabling gravity

# UTILITY FUNCTIONS

func _handle_fall() -> void:
    print("Car fell off the edge, resetting level...")
    
    var level_manager = get_node("/root/Main/LevelManager")
    if level_manager and level_manager.has_method("schedule_level_reset"):
        level_manager.schedule_level_reset()

func clear_passengers() -> void:
    # Clean up any indicators for current passengers
    for passenger in current_passengers:
        if passenger and is_instance_valid(passenger):
            # If passenger has an indicator that was reparented, remove it
            if passenger.destination_indicator and passenger.destination_indicator.get_parent() != passenger:
                passenger.destination_indicator.queue_free()
    
    current_passengers.clear()
    nearby_passengers.clear()
    nearby_destinations.clear()

func check_level_completion() -> void:
    # Get the level from the main scene
    var level_manager = get_node("/root/Main/LevelManager")
    if not level_manager:
        return
    
    var current_level = level_manager.current_level_instance
    if not current_level:
        return
    
    # Check if all required passengers have been delivered
    var all_delivered = true
    for node in get_tree().get_nodes_in_group("passengers"):
        if not node.is_delivered and not node.is_ragdolling:
            all_delivered = false
            break
    
    # Also check if there are any passengers still in the car
    if current_passengers.size() > 0:
        all_delivered = false
    
    if all_delivered:
        print("All passengers delivered! Level completed.")
        emit_signal("level_completed")
        
        # Transition to next level if available
        if current_level.has_method("get") and current_level.get("next_level_path") != "":
            var next_level = current_level.next_level_path
            var transition_delay = 2.0
            
            if current_level.has_method("get") and current_level.get("transition_delay") > 0:
                transition_delay = current_level.transition_delay
            
            var timer = get_tree().create_timer(transition_delay)
            timer.timeout.connect(func():
                emit_signal("door_entered", next_level, Vector2i(1, 1))
            )
