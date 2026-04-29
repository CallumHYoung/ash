extends Node3D

const RESPAWN_DEPTH: float = 16100.0
const SPAWN_POSITION: Vector3 = Vector3(0, 11.5, 145)
const HEALTH_FILL_MAX_WIDTH: float = 256.0

@onready var player: CharacterBody3D = $Player
@onready var depth_label: Label = $HUD/DepthLabel
@onready var health_fill: ColorRect = $HUD/HealthFill
@onready var health_label: Label = $HUD/HealthLabel


func _ready() -> void:
	# Belt-and-suspenders for project setting propagation: force the window to
	# be resizable and bordered at runtime, so F5 from the editor honors it
	# even if the project hasn't been reloaded since the setting was added.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)


func _process(_delta: float) -> void:
	var depth := int(max(0.0, -player.global_position.y))
	depth_label.text = "Depth: %d m" % depth

	var hp_frac := clampf(player.health / player.MAX_HEALTH, 0.0, 1.0)
	health_fill.size.x = HEALTH_FILL_MAX_WIDTH * hp_frac
	health_label.text = str(int(player.health))

	# Falling out of the world routes through the same death flow as taking
	# fatal damage, so the player ends up at their last checkpoint.
	if -player.global_position.y > RESPAWN_DEPTH:
		player.die()
	if Input.is_action_just_pressed("restart"):
		_full_restart()


func _full_restart() -> void:
	player.global_position = SPAWN_POSITION
	player.velocity = Vector3.ZERO
	player.health = player.MAX_HEALTH
	player.checkpoint_position = SPAWN_POSITION
