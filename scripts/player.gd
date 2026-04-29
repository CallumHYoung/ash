extends CharacterBody3D

# Controls (FPS):
#   W A S D ............ move (relative to camera yaw)
#   Mouse .............. look around
#   Space .............. jump (when grounded)
#   Left Mouse (hold) .. fire grapple toward crosshair, hold to stay attached
#   Shift (held) ....... reel rope shorter while attached
#   R .................. respawn at top
#   Esc ................ release mouse cursor; click again to recapture

const SPEED: float = 6.5
const JUMP_VELOCITY: float = 7.5
const AIR_CONTROL: float = 8.0
const MOUSE_SENSITIVITY: float = 0.0022

@export var grapple_max_distance: float = 80.0
@export var grapple_reel_speed: float = 8.0
@export var grapple_swing_force: float = 22.0
@export var grapple_min_length: float = 1.5

@onready var camera: Camera3D = $Camera3D
@onready var rope_mesh: MeshInstance3D = $RopeLine
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

var rope_immediate := ImmediateMesh.new()
var grapple_attached: bool = false
var grapple_anchor: Vector3 = Vector3.ZERO
var grapple_length: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
var _consume_next_grapple: bool = false


func _ready() -> void:
	rope_mesh.mesh = rope_immediate
	rope_mesh.top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.92, 0.85, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mesh.material_override = mat
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		rotation.y = _yaw
		camera.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_consume_next_grapple = true


func _physics_process(delta: float) -> void:
	_handle_grapple_input()

	if not is_on_floor():
		velocity.y -= gravity * delta

	if grapple_attached:
		_apply_swing(delta)
		_clamp_outward_velocity()
	else:
		var input_dir := Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_forward", "move_back")
		)
		var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
		if dir.length() > 0.0:
			dir = dir.normalized()
		var target := dir * SPEED
		if is_on_floor():
			velocity.x = target.x
			velocity.z = target.z
		else:
			velocity.x = move_toward(velocity.x, target.x, AIR_CONTROL * delta)
			velocity.z = move_toward(velocity.z, target.z, AIR_CONTROL * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	if grapple_attached:
		_constrain_to_rope()

	_draw_rope()


func _handle_grapple_input() -> void:
	if Input.is_action_just_pressed("grapple"):
		if _consume_next_grapple:
			_consume_next_grapple = false
		else:
			_try_fire_grapple()
	if Input.is_action_just_released("grapple"):
		grapple_attached = false


func _try_fire_grapple() -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var to := from + forward * grapple_max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [get_rid()])
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		grapple_anchor = hit["position"]
		grapple_length = max(grapple_min_length, global_position.distance_to(grapple_anchor))
		grapple_attached = true


func _apply_swing(delta: float) -> void:
	if Input.is_action_pressed("reel"):
		grapple_length = max(grapple_min_length, grapple_length - grapple_reel_speed * delta)
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	if dir.length() > 0.0:
		dir = dir.normalized()
	velocity += dir * grapple_swing_force * delta


func _clamp_outward_velocity() -> void:
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	if dist == 0.0 or dist < grapple_length - 0.05:
		return
	var dir := to_anchor / dist
	var outward := velocity.dot(-dir)
	if outward > 0.0:
		velocity += dir * outward


func _constrain_to_rope() -> void:
	var to_anchor := grapple_anchor - global_position
	var dist := to_anchor.length()
	if dist <= grapple_length or dist == 0.0:
		return
	var dir := to_anchor / dist
	global_position = grapple_anchor - dir * grapple_length


func _draw_rope() -> void:
	rope_immediate.clear_surfaces()
	if not grapple_attached:
		return
	rope_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	# Offset slightly below camera so the rope isn't clipped by the near plane.
	rope_immediate.surface_add_vertex(camera.global_position - camera.global_basis.y * 0.15)
	rope_immediate.surface_add_vertex(grapple_anchor)
	rope_immediate.surface_end()
