extends Node3D

@onready var particles = $GPUParticles3D
@onready var light = $OmniLight3D
@onready var timer = $Timer

func _ready():
	# Connect timer signal
	if not timer.timeout.is_connected(_on_timer_timeout):
		timer.timeout.connect(_on_timer_timeout)
	
	# Auto-start particles
	start()

# Start emitting particles
func start():
	if particles:
		particles.emitting = true
	
	if light:
		# Animate the light
		var tween = create_tween()
		tween.tween_property(light, "light_energy", 3.0, 0.1)
		tween.tween_property(light, "light_energy", 0.0, 1.0)

# Set parameters for the effect
func set_parameters(color: Color, amount: int = 20):
	if particles:
		# Set amount
		particles.amount = amount
		
		# Update material color if possible
		if particles.draw_pass_1 and particles.draw_pass_1.get_material():
			var material = particles.draw_pass_1.get_material()
			if material is StandardMaterial3D:
				material.albedo_color = color
	
	if light:
		light.light_color = color

# Clean up the effect
func _on_timer_timeout():
	queue_free()
