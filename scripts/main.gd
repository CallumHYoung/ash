extends Node3D

const RESPAWN_DEPTH: float = 290.0
const SPAWN_POSITION: Vector3 = Vector3(0, 3, 0)

@onready var player: CharacterBody3D = $Player
@onready var depth_label: Label = $HUD/DepthLabel


func _process(_delta: float) -> void:
	var depth := int(max(0.0, -player.global_position.y))
	depth_label.text = "Depth: %d m" % depth

	if -player.global_position.y > RESPAWN_DEPTH:
		_respawn()
	if Input.is_action_just_pressed("restart"):
		_respawn()


func _respawn() -> void:
	player.global_position = SPAWN_POSITION
	player.velocity = Vector3.ZERO
