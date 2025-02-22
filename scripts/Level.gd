extends Node3D

@export var grid_width: int = 10
@export var grid_height: int = 10
@export var cell_size: float = 1.0

func _ready() -> void:
	# Example only. If you are generating the entire floor in the EditorScript,
	# you might NOT do it here. Or you can do a partial spawn for debugging.
	pass
