@tool
extends StaticBody3D
class_name Cavern

# Procedural cavern: a vertical tube with rings of vertices, each displaced
# along its radial direction by 3D simplex noise. Closed top and bottom caps.
# Generation is deterministic from `noise_seed`, so the same seed always
# produces the same cavern — no need to bake to disk.

@export var noise_seed: int = 1337: set = _set_noise_seed
@export var top_y: float = 10.0: set = _set_top_y
@export var height: float = 320.0: set = _set_height
@export var base_radius: float = 22.0: set = _set_base_radius
@export var rings: int = 200: set = _set_rings
@export var radial_segments: int = 64: set = _set_radial_segments
@export_range(0.0, 10.0, 0.1) var displacement: float = 4.0: set = _set_displacement
@export var noise_frequency: float = 0.06: set = _set_noise_frequency
@export_range(1, 6) var noise_octaves: int = 4: set = _set_noise_octaves
@export var bulge_amplitude: float = 2.5: set = _set_bulge_amplitude
@export var bulge_frequency: float = 3.0: set = _set_bulge_frequency
@export_range(0.5, 4.0, 0.1) var noise_vertical_stretch: float = 1.6: set = _set_noise_vertical_stretch
@export var rebuild_now: bool = false: set = _set_rebuild_now

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

	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = noise_frequency
	noise.fractal_octaves = noise_octaves
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var seg: int = max(8, radial_segments)
	var ring_count: int = max(2, rings)
	var bottom_y: float = top_y - height
	var inv_stretch: float = 1.0 / max(0.1, noise_vertical_stretch)

	# Build vertex grid
	var positions := PackedVector3Array()
	positions.resize((ring_count + 1) * seg + 2)

	for r in range(ring_count + 1):
		var t: float = float(r) / float(ring_count)
		var y: float = top_y - t * height
		var bulge: float = sin(t * PI * bulge_frequency) * bulge_amplitude
		for s in range(seg):
			var theta: float = float(s) / float(seg) * TAU
			var dx: float = cos(theta)
			var dz: float = sin(theta)
			# Sample 3D noise on the unit cylinder so the seam wraps seamlessly.
			var sample := Vector3(dx, y * inv_stretch, dz)
			var n_val: float = noise.get_noise_3dv(sample)
			var radius: float = base_radius + bulge + n_val * displacement
			positions[r * seg + s] = Vector3(dx * radius, y, dz * radius)

	var top_center_idx: int = (ring_count + 1) * seg
	var bot_center_idx: int = top_center_idx + 1
	positions[top_center_idx] = Vector3(0, top_y, 0)
	positions[bot_center_idx] = Vector3(0, bottom_y, 0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in positions:
		st.add_vertex(p)

	# Walls — winding chosen so generated normals point inward (player inside).
	for r in range(ring_count):
		for s in range(seg):
			var s2: int = (s + 1) % seg
			var i00: int = r * seg + s
			var i01: int = r * seg + s2
			var i10: int = (r + 1) * seg + s
			var i11: int = (r + 1) * seg + s2
			st.add_index(i00); st.add_index(i10); st.add_index(i01)
			st.add_index(i01); st.add_index(i10); st.add_index(i11)

	# Top cap (normals point -Y, visible from below).
	for s in range(seg):
		var s2: int = (s + 1) % seg
		st.add_index(top_center_idx)
		st.add_index(s)
		st.add_index(s2)

	# Bottom cap (normals point +Y, visible from above).
	var base_idx: int = ring_count * seg
	for s in range(seg):
		var s2: int = (s + 1) % seg
		st.add_index(bot_center_idx)
		st.add_index(base_idx + s2)
		st.add_index(base_idx + s)

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.18, 0.16, 0.2, 1)
		_material.roughness = 0.95
	mesh.surface_set_material(0, _material)

	_mesh_instance.mesh = mesh
	_collision.shape = mesh.create_trimesh_shape()


func _set_noise_seed(v: int) -> void: noise_seed = v; _queue_rebuild()
func _set_top_y(v: float) -> void: top_y = v; _queue_rebuild()
func _set_height(v: float) -> void: height = v; _queue_rebuild()
func _set_base_radius(v: float) -> void: base_radius = v; _queue_rebuild()
func _set_rings(v: int) -> void: rings = v; _queue_rebuild()
func _set_radial_segments(v: int) -> void: radial_segments = v; _queue_rebuild()
func _set_displacement(v: float) -> void: displacement = v; _queue_rebuild()
func _set_noise_frequency(v: float) -> void: noise_frequency = v; _queue_rebuild()
func _set_noise_octaves(v: int) -> void: noise_octaves = v; _queue_rebuild()
func _set_bulge_amplitude(v: float) -> void: bulge_amplitude = v; _queue_rebuild()
func _set_bulge_frequency(v: float) -> void: bulge_frequency = v; _queue_rebuild()
func _set_noise_vertical_stretch(v: float) -> void: noise_vertical_stretch = v; _queue_rebuild()
func _set_rebuild_now(_v: bool) -> void:
	rebuild_now = false
	if is_inside_tree():
		_build()
