extends CharacterBody3D

# Controls (FPS):
#   W A S D ............ move (relative to camera yaw)
#   Mouse .............. look around
#   Space .............. jump (when grounded)
#   Left Mouse (hold) .. fire grapple toward crosshair, hold to stay attached
#   Shift (held) ....... reel rope shorter while attached
#   R .................. respawn at top
#   Esc ................ open pause menu

const SPEED: float = 6.5
const JUMP_VELOCITY: float = 7.5
const AIR_CONTROL: float = 3.0
const FALL_GRAVITY_MULT: float = 1.45
const JUMP_CUT_FACTOR: float = 0.45
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.10
const MOUSE_SENSITIVITY: float = 0.0022

# Ledge mantle. The forward+head ray finds the wall, then a downward probe
# looks for a flat top in a window straddling head height; the climb tween
# rises vertically first and steps onto the ledge.
const LEDGE_PROBE_FORWARD: float = 0.55
const LEDGE_PROBE_TOP: float = 1.20
const LEDGE_PROBE_BOTTOM: float = 0.50
const LEDGE_CLEARANCE: float = 1.80
const LEDGE_FORWARD_PUSH: float = 0.50
const LEDGE_RISE_DURATION: float = 0.45
const LEDGE_FORWARD_DURATION: float = 0.25
const CAPSULE_HALF_HEIGHT: float = 0.90

# Impacts below this speed are free; damage scales above it.
const IMPACT_DAMAGE_THRESHOLD: float = 12.0
const IMPACT_DAMAGE_EXPONENT: float = 1.7
const IMPACT_DAMAGE_SCALE: float = 0.4
const MAX_HEALTH: float = 100.0

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
var health: float = MAX_HEALTH
var checkpoint_position: Vector3 = Vector3.ZERO
var input_locked: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _last_checkpoint_floor_id: int = 0
var _coyote_remaining: float = 0.0
var _jump_buffer_remaining: float = 0.0
var _climbing: bool = false


func _ready() -> void:
	rope_mesh.mesh = rope_immediate
	rope_mesh.top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.92, 0.85, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mesh.material_override = mat
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	checkpoint_position = global_position


func _input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		rotation.y = _yaw
		camera.rotation.x = _pitch


func lock_and_look_at(target: Vector3, duration: float = 0.45) -> void:
	# Cinematic lock: stop the player, drop any active grapple, and tween the
	# camera onto `target`. Keep `_yaw`/`_pitch` in sync with the visible
	# rotation so the next mouse motion after unlock doesn't snap.
	input_locked = true
	grapple_attached = false
	velocity = Vector3.ZERO
	var look_origin := camera.global_position
	var dx: float = target.x - look_origin.x
	var dy: float = target.y - look_origin.y
	var dz: float = target.z - look_origin.z
	var horiz: float = sqrt(dx * dx + dz * dz)
	var raw_yaw: float = atan2(-dx, -dz)
	var target_pitch: float = clamp(atan2(dy, horiz), -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	# Take the shortest angular path to avoid spinning past PI.
	var target_yaw: float = _yaw + wrapf(raw_yaw - _yaw, -PI, PI)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_yaw", target_yaw, duration)
	t.tween_property(self, "rotation:y", target_yaw, duration)
	t.tween_property(self, "_pitch", target_pitch, duration)
	t.tween_property(camera, "rotation:x", target_pitch, duration)


func unlock_input() -> void:
	input_locked = false


func _physics_process(delta: float) -> void:
	if _climbing:
		# The ledge tween fully owns position and camera while a mantle is in
		# progress; skipping physics keeps gravity and collisions from fighting
		# the animation.
		return

	if input_locked:
		_apply_gravity(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_draw_rope()
		return

	_handle_grapple_input()

	if is_on_floor():
		_coyote_remaining = COYOTE_TIME
	else:
		_coyote_remaining = max(0.0, _coyote_remaining - delta)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_remaining = JUMP_BUFFER_TIME
	else:
		_jump_buffer_remaining = max(0.0, _jump_buffer_remaining - delta)

	# Variable height: releasing jump while still rising cuts the impulse so
	# tapped jumps are short and held jumps reach full height.
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= JUMP_CUT_FACTOR

	_apply_gravity(delta)

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

	# Resolve a buffered jump: prefer a ledge mantle if one is in reach,
	# otherwise fall through to a normal (coyote-forgiving) jump.
	if _jump_buffer_remaining > 0.0:
		if _try_ledge_climb():
			_jump_buffer_remaining = 0.0
			return
		if _coyote_remaining > 0.0:
			velocity.y = JUMP_VELOCITY
			_jump_buffer_remaining = 0.0
			_coyote_remaining = 0.0

	var pre_velocity := velocity
	var was_on_floor := is_on_floor()
	move_and_slide()

	_process_impacts(pre_velocity, was_on_floor)
	_update_checkpoint()

	if grapple_attached:
		_constrain_to_rope()

	_draw_rope()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity
	if velocity.y < 0.0:
		g *= FALL_GRAVITY_MULT
	velocity.y -= g * delta


func _process_impacts(pre_velocity: Vector3, was_on_floor: bool) -> void:
	# Pick the worst impact this frame so we never double-count, and so the
	# damage curve is driven by the most violent contact rather than several
	# small grazes summed together.
	var worst_speed: float = 0.0

	if is_on_floor() and not was_on_floor:
		worst_speed = absf(pre_velocity.y)

	for i in get_slide_collision_count():
		var coll := get_slide_collision(i)
		var n := coll.get_normal()
		# Floor handled above; only count walls/ceilings here.
		if n.y > 0.7:
			continue
		var into_speed := -pre_velocity.dot(n)
		if into_speed > worst_speed:
			worst_speed = into_speed

	var dmg := _damage_for_speed(worst_speed)
	if dmg > 0.0:
		take_damage(dmg)


func _damage_for_speed(speed: float) -> float:
	if speed <= IMPACT_DAMAGE_THRESHOLD:
		return 0.0
	var excess := speed - IMPACT_DAMAGE_THRESHOLD
	return pow(excess, IMPACT_DAMAGE_EXPONENT) * IMPACT_DAMAGE_SCALE


func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = max(0.0, health - amount)
	if health <= 0.0:
		die()


func die() -> void:
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	grapple_attached = false
	global_position = checkpoint_position
	# Force the next floor contact to register as a fresh checkpoint, even if
	# we land on the same platform we respawned on.
	_last_checkpoint_floor_id = 0


func _update_checkpoint() -> void:
	if not is_on_floor():
		return
	var floor_collider: Object = null
	for i in get_slide_collision_count():
		var coll := get_slide_collision(i)
		if coll.get_normal().y > 0.7:
			floor_collider = coll.get_collider()
			break
	if floor_collider == null:
		return
	# Only platforms count — the cavern's bottom cap and any stray ledges
	# would otherwise become respawn traps.
	if not (floor_collider is Node) or not (floor_collider as Node).is_in_group("checkpoint"):
		return
	var id := floor_collider.get_instance_id()
	if id == _last_checkpoint_floor_id:
		return
	_last_checkpoint_floor_id = id
	checkpoint_position = global_position


func _handle_grapple_input() -> void:
	if Input.is_action_just_pressed("grapple"):
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


func _try_ledge_climb() -> bool:
	if grapple_attached:
		return false
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return false
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state

	# 1) Wall in front at head height. A near-vertical normal filters out
	#    ramps so we don't try to mantle a slope.
	var head_pos := global_position + Vector3.UP * 0.7
	var wall_query := PhysicsRayQueryParameters3D.create(
		head_pos, head_pos + forward * LEDGE_PROBE_FORWARD, 0xFFFFFFFF, [get_rid()]
	)
	var wall_hit := space.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return false
	if absf(Vector3(wall_hit["normal"]).y) > 0.4:
		return false

	# 2) Cast down from above-and-forward; only ledges in a window straddling
	#    head height qualify ("close enough for the player to grab").
	var probe_xz := global_position + forward * LEDGE_PROBE_FORWARD
	var probe_top := Vector3(probe_xz.x, global_position.y + LEDGE_PROBE_TOP, probe_xz.z)
	var probe_bottom := Vector3(probe_xz.x, global_position.y + LEDGE_PROBE_BOTTOM, probe_xz.z)
	var ledge_query := PhysicsRayQueryParameters3D.create(
		probe_top, probe_bottom, 0xFFFFFFFF, [get_rid()]
	)
	var ledge_hit := space.intersect_ray(ledge_query)
	if ledge_hit.is_empty():
		return false
	if Vector3(ledge_hit["normal"]).y < 0.7:
		return false

	# 3) Need a standing capsule's worth of headroom above the ledge or the
	#    mantle would teleport into a low ceiling.
	var ledge_pos: Vector3 = ledge_hit["position"]
	var clearance_query := PhysicsRayQueryParameters3D.create(
		ledge_pos + Vector3.UP * 0.05,
		ledge_pos + Vector3.UP * LEDGE_CLEARANCE,
		0xFFFFFFFF, [get_rid()]
	)
	if not space.intersect_ray(clearance_query).is_empty():
		return false

	_begin_ledge_climb(ledge_pos, forward)
	return true


func _begin_ledge_climb(ledge_pos: Vector3, forward: Vector3) -> void:
	_climbing = true
	input_locked = true
	grapple_attached = false
	velocity = Vector3.ZERO

	var rise_target := global_position
	rise_target.y = ledge_pos.y + CAPSULE_HALF_HEIGHT
	var final_target := rise_target + forward * LEDGE_FORWARD_PUSH

	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "global_position", rise_target, LEDGE_RISE_DURATION).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", final_target, LEDGE_FORWARD_DURATION).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(_finish_ledge_climb)

	# Camera "struggle": dip the pitch hard during the rise, overshoot a bit,
	# then settle as the body steps onto the ledge. Phases sum to the full
	# climb duration so the camera lands upright on completion.
	var base_pitch := _pitch
	var cam_t := create_tween().set_trans(Tween.TRANS_SINE)
	cam_t.tween_property(camera, "rotation:x", base_pitch - 0.10, LEDGE_RISE_DURATION * 0.40)
	cam_t.tween_property(camera, "rotation:x", base_pitch + 0.04, LEDGE_RISE_DURATION * 0.50)
	cam_t.tween_property(camera, "rotation:x", base_pitch, LEDGE_FORWARD_DURATION + LEDGE_RISE_DURATION * 0.10)


func _finish_ledge_climb() -> void:
	_climbing = false
	input_locked = false
	velocity = Vector3.ZERO
