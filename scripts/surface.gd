@tool
extends StaticBody3D
class_name Surface

# Procedural bumpy grass surface above the cavern. A polar grid of vertices
# from `inner_radius` (the cavern rim) out to `outer_radius`, with low-amp
# noise on Y. The inner ring samples the cavern's rim noise so the hole edge
# tracks the cavern wall instead of cutting straight across it.

@export var surface_y: float = 10.0: set = _set_y
@export var inner_radius: float = 110.0: set = _set_inner
@export var outer_radius: float = 280.0: set = _set_outer
@export var rings: int = 64: set = _set_rings
@export var radial_segments: int = 96: set = _set_segs
@export_range(0.0, 4.0, 0.05) var bump_amplitude: float = 0.5: set = _set_bumpa
@export var bump_frequency: float = 0.05: set = _set_bumpf
@export_range(1, 6) var bump_octaves: int = 3: set = _set_bumpo
# Flatten bumps within this distance of the inner rim so it stays clean.
@export var rim_flatten_distance: float = 12.0: set = _set_rim_flat

@export_group("Cavern rim match")
@export var rim_match_seed: int = 1337: set = _set_rim_seed
@export var rim_displacement: float = 4.0: set = _set_rim_disp
@export var rim_noise_frequency: float = 0.06: set = _set_rim_freq
@export_range(1, 6) var rim_noise_octaves: int = 4: set = _set_rim_oct
@export var rim_noise_vertical_stretch: float = 1.6: set = _set_rim_vstr
# Tucks the inner edge slightly inside the cavern wall so the seam is hidden.
@export var rim_overlap: float = 1.5: set = _set_rim_overlap

@export_group("")
@export var albedo: Color = Color(0.32, 0.4, 0.2): set = _set_albedo
@export_range(0.0, 1.0, 0.05) var roughness: float = 0.95: set = _set_rough
@export var rebuild_now: bool = false: set = _set_rebuild

var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _material: StandardMaterial3D = null
var _build_queued: bool = false


func _ready() -> void:
	_ensure_children()
	_build()


func _ensure_children() -> void:
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = get_node_or_null("MeshInstance3D")
		if _mesh_instance == null:
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "MeshInstance3D"
			add_child(_mesh_instance)
	if not is_instance_valid(_collision):
		_collision = get_node_or_null("CollisionShape3D")
		if _collision == null:
			_collision = CollisionShape3D.new()
			_collision.name = "CollisionShape3D"
			add_child(_collision)


func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if _build_queued:
		return
	_build_queued = true
	call_deferred("_build")


func _build() -> void:
	_build_queued = false
	_ensure_children()

	var bump_noise := FastNoiseLite.new()
	bump_noise.seed = rim_match_seed * 17 + 3
	bump_noise.frequency = bump_frequency
	bump_noise.fractal_octaves = bump_octaves
	bump_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	# Same parameters as cavern.gd so the rim reads the identical noise field.
	var rim_noise := FastNoiseLite.new()
	rim_noise.seed = rim_match_seed
	rim_noise.frequency = rim_noise_frequency
	rim_noise.fractal_octaves = rim_noise_octaves
	rim_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var inv_stretch: float = 1.0 / max(0.1, rim_noise_vertical_stretch)

	var seg: int = max(8, radial_segments)
	var ring_count: int = max(2, rings)

	var positions := PackedVector3Array()
	positions.resize((ring_count + 1) * seg)

	var rim_radii := PackedFloat32Array()
	rim_radii.resize(seg)
	for s in range(seg):
		var theta: float = float(s) / float(seg) * TAU
		var dx: float = cos(theta)
		var dz: float = sin(theta)
		var n_val: float = rim_noise.get_noise_3dv(Vector3(dx, surface_y * inv_stretch, dz))
		rim_radii[s] = inner_radius + n_val * rim_displacement - rim_overlap

	for r in range(ring_count + 1):
		var t: float = float(r) / float(ring_count)
		for s in range(seg):
			var theta: float = float(s) / float(seg) * TAU
			var dx: float = cos(theta)
			var dz: float = sin(theta)
			var rim_r: float = rim_radii[s]
			var radius: float = lerp(rim_r, outer_radius, t)
			# Suppress bumps near the rim so the lip stays clean and cosmetic.
			var dist_from_rim: float = radius - rim_r
			var flatten: float = clamp(dist_from_rim / max(0.001, rim_flatten_distance), 0.0, 1.0)
			var bump: float = bump_noise.get_noise_2d(dx * radius, dz * radius) * bump_amplitude * flatten
			positions[r * seg + s] = Vector3(dx * radius, surface_y + bump, dz * radius)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in positions:
		st.add_vertex(p)

	for r in range(ring_count):
		for s in range(seg):
			var s2: int = (s + 1) % seg
			var i00: int = r * seg + s
			var i01: int = r * seg + s2
			var i10: int = (r + 1) * seg + s
			var i11: int = (r + 1) * seg + s2
			st.add_index(i00); st.add_index(i01); st.add_index(i10)
			st.add_index(i01); st.add_index(i11); st.add_index(i10)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	if _material == null:
		_material = StandardMaterial3D.new()
	_material.albedo_color = albedo
	_material.roughness = roughness
	# Render both sides — sidesteps any winding-convention confusion and keeps
	# the surface visible from inside the chasm too.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, _material)

	_mesh_instance.mesh = mesh
	# Trimesh collision is one-sided by default in Godot — if our winding has
	# the normals pointing the wrong way, the player would tunnel right through
	# from above and only collide from below (matching the "falls through then
	# gets stuck" symptom). backface_collision makes the triangles solid both
	# ways, so the player always lands on the ground.
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	_collision.shape = shape
	if not Engine.is_editor_hint():
		print("[Surface] built: ", positions.size(), " verts, ", (ring_count * seg * 2),
			" tris, y=", surface_y, " inner~", rim_radii[0], " outer=", outer_radius)


func _set_y(v: float) -> void: surface_y = v; _queue_rebuild()
func _set_inner(v: float) -> void: inner_radius = v; _queue_rebuild()
func _set_outer(v: float) -> void: outer_radius = v; _queue_rebuild()
func _set_rings(v: int) -> void: rings = v; _queue_rebuild()
func _set_segs(v: int) -> void: radial_segments = v; _queue_rebuild()
func _set_bumpa(v: float) -> void: bump_amplitude = v; _queue_rebuild()
func _set_bumpf(v: float) -> void: bump_frequency = v; _queue_rebuild()
func _set_bumpo(v: int) -> void: bump_octaves = v; _queue_rebuild()
func _set_rim_flat(v: float) -> void: rim_flatten_distance = v; _queue_rebuild()
func _set_rim_seed(v: int) -> void: rim_match_seed = v; _queue_rebuild()
func _set_rim_disp(v: float) -> void: rim_displacement = v; _queue_rebuild()
func _set_rim_freq(v: float) -> void: rim_noise_frequency = v; _queue_rebuild()
func _set_rim_oct(v: int) -> void: rim_noise_octaves = v; _queue_rebuild()
func _set_rim_vstr(v: float) -> void: rim_noise_vertical_stretch = v; _queue_rebuild()
func _set_rim_overlap(v: float) -> void: rim_overlap = v; _queue_rebuild()
func _set_albedo(v: Color) -> void: albedo = v; _queue_rebuild()
func _set_rough(v: float) -> void: roughness = v; _queue_rebuild()
func _set_rebuild(_v: bool) -> void:
	rebuild_now = false
	if is_inside_tree():
		_build()
