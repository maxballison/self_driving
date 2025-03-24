# Main.gd
extends Node

# Core components
@onready var player = $Player
@onready var tutorial_window = $TutorialWindow
@onready var interpreter = $ScriptInterpreter
@onready var level_manager = $LevelManager
@onready var camera = $Camera3D

# Sound effects
var audio_players = {}
var sounds = {
#	"drive": preload("res://sounds/drive.wav") if ResourceLoader.exists("res://sounds/drive.wav") else null,
#	"turn": preload("res://sounds/turn.wav") if ResourceLoader.exists("res://sounds/turn.wav") else null,
#	"pickup": preload("res://sounds/pickup.wav") if ResourceLoader.exists("res://sounds/pickup.wav") else null,
#	"delivery": preload("res://sounds/delivery.wav") if ResourceLoader.exists("res://sounds/delivery.wav") else null,
#	"error": preload("res://sounds/error.wav") if ResourceLoader.exists("res://sounds/error.wav") else null,
#	"success": preload("res://sounds/success.wav") if ResourceLoader.exists("res://sounds/success.wav") else null,
#	"crash": preload("res://sounds/crash.wav") if ResourceLoader.exists("res://sounds/crash.wav") else null,
}

# Visual effects
var particle_scene = preload("res://ParticleEffect.tscn") if ResourceLoader.exists("res://ParticleEffect.tscn") else null

@export var run_delay = 0.1

# Game settings
@export var enable_sounds = true
@export var enable_particles = true
@export var screen_shake_amount = 0.3

func _ready():
	# Setup interpreter
	interpreter.player = player
	
	# Initialize tutorial system
	if level_manager:
		if not level_manager.is_connected("level_switched", Callable(self, "_on_level_switched")):
			level_manager.connect("level_switched", Callable(self, "_on_level_switched"))
		
		# Manually trigger first tutorial
		_on_level_switched()
	
	# Initialize audio players
	if enable_sounds:
		_setup_audio_players()
	
	# Debug info
	print("Main scene initialized")
	print("Tutorial window position: ", tutorial_window.position)
	print("Tutorial window size: ", tutorial_window.size)

func _on_level_switched():
	# Show tutorial when level changes
	if tutorial_window:
		tutorial_window.visible = true
		
		# If TutorialManager not available, set default messages
		if not TutorialManagers:
			var current_level = level_manager.current_level_instance.scene_file_path if level_manager.current_level_instance else "unknown"
			var default_messages = [
				"[b]Welcome to Level " + current_level.get_basename().get_file() + "![/b]",
				"Use the [color=#80CCFF]Code Editor[/color] to control your character.\n\nTry commands like:\n[code]drive()[/code]\n[code]turn_left()[/code]",
				"Click the [color=#80FF80]Run[/color] button to execute your code."
			]
			tutorial_window.set_tutorial_messages(default_messages)

# Set up audio players for sound effects
func _setup_audio_players():
	# Create audio players for each sound
	for sound_name in sounds.keys():
		if sounds[sound_name] != null:
			var audio_player = AudioStreamPlayer.new()
			audio_player.stream = sounds[sound_name]
			audio_player.volume_db = -10  # Default volume level
			audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
			add_child(audio_player)
			audio_players[sound_name] = audio_player
		else:
			# Create dummy audio players to avoid errors
			audio_players[sound_name] = null
			
	print("Audio system initialized with ", audio_players.size(), " sound effects")

# Play a sound effect by name
func play_sound(sound_name: String, volume_db: float = -10, pitch_scale: float = 1.0):
	if not enable_sounds:
		return
	
	if audio_players.has(sound_name) and audio_players[sound_name] != null:
		var audio_player = audio_players[sound_name]
		audio_player.volume_db = volume_db
		audio_player.pitch_scale = pitch_scale
		audio_player.play()
		
		# For certain sounds, add screen shake
		if sound_name == "crash" or sound_name == "success":
			_shake_camera(screen_shake_amount if sound_name == "crash" else screen_shake_amount * 0.5)
	else:
		print("Sound not found: ", sound_name)

# Create a particle effect at the specified position
func spawn_particles(position: Vector3, color: Color = Color(1, 1, 1), amount: int = 20):
	if not enable_particles or particle_scene == null:
		return
	
	var particles = particle_scene.instantiate()
	add_child(particles)
	particles.global_position = position + Vector3(0, 0.5, 0)
	
	# Set particle properties if exposed
	if particles.has_method("set_parameters"):
		particles.set_parameters(color, amount)
	elif particles.has_node("GPUParticles3D"):
		var particle_node = particles.get_node("GPUParticles3D")
		if particle_node:
			# Try to set material parameters
			if particle_node.draw_pass_1 and particle_node.draw_pass_1.get_material():
				var material = particle_node.draw_pass_1.get_material()
				if material is StandardMaterial3D:
					material.albedo_color = color
	
	# Auto-free the particles after they're done
	if particles.has_method("start"):
		particles.start()
	else:
		# Fallback: just queue free after a delay
		var timer = get_tree().create_timer(2.0)
		timer.timeout.connect(func(): particles.queue_free())

# Shake the camera for visual feedback
func _shake_camera(intensity: float = 0.3):
	if camera:
		var tween = create_tween()
		var original_pos = camera.position
		
		# Shake sequence
		tween.tween_property(camera, "position", original_pos + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * intensity, 0.1)
		tween.tween_property(camera, "position", original_pos, 0.1)
		tween.tween_property(camera, "position", original_pos + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5)) * intensity * 0.7, 0.1)
		tween.tween_property(camera, "position", original_pos, 0.1)
