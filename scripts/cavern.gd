@tool
extends StaticBody3D
class_name Cavern

const WALL_TEXTURE: Texture2D = preload("res://str_stonerubble.bmp")

# Procedural cavern: a vertical tube with rings of vertices, each displaced
# along its radial direction by 3D simplex noise. Closed top and bottom caps.
# Generation is deterministic from `noise_seed`, so the same seed always
# produces the same cavern — no need to bake to disk.

@export var noise_seed: int = 1337: set = _set_noise_seed
@export var top_y: float = 10.0: set = _set_top_y
@export var height: float = 320.0: set = _set_height
@export var base_radius: float = 110.0: set = _set_base_radius
@export var rings: int = 500: set = _set_rings
@export var radial_segments: int = 64: set = _set_radial_segments
@export_range(0.0, 10.0, 0.1) var displacement: float = 4.0: set = _set_displacement
@export var noise_frequency: float = 0.06: set = _set_noise_frequency
@export_range(1, 6) var noise_octaves: int = 4: set = _set_noise_octaves
@export var bulge_amplitude: float = 2.5: set = _set_bulge_amplitude
@export var bulge_frequency: float = 3.0: set = _set_bulge_frequency
@export_range(0.5, 4.0, 0.1) var noise_vertical_stretch: float = 1.6: set = _set_noise_vertical_stretch
@export var open_top: bool = true: set = _set_open_top

@export_group("Profile")
# Chambers are ellipsoidal bulges layered on top of the tube. With aspect=1.0
# the bulge is a perfect sphere; aspect>1 stretches it tall (vertical pillar
# rooms), aspect<1 squashes it (low-ceiling wide caverns where you can pack
# in jagged rocks). Sized as "extra above base_radius" so a chamber always
# pokes outside the tube. Stratified along height from `noise_seed`.
@export_range(0, 40) var chamber_count: int = 12: set = _set_chamber_count
@export var chamber_extra_radius_min: float = 20.0: set = _set_chamber_extra_min
@export var chamber_extra_radius_max: float = 130.0: set = _set_chamber_extra_max
@export_range(0.3, 3.0, 0.05) var chamber_aspect_min: float = 0.55: set = _set_chamber_aspect_min
@export_range(0.3, 3.0, 0.05) var chamber_aspect_max: float = 1.8: set = _set_chamber_aspect_max
# Chokepoints pinch the tube radius down via a smooth bell, creating tight
# squeeze sections between chambers.
@export_range(0, 40) var chokepoint_count: int = 8: set = _set_chokepoint_count
@export_range(0.0, 0.95, 0.01) var chokepoint_strength: float = 0.55: set = _set_chokepoint_strength
@export var chokepoint_half_height: float = 16.0: set = _set_chokepoint_half_height

@export_group("Torches")
@export_range(0, 40) var torch_count: int = 12: set = _set_torch_count
@export var torch_color: Color = Color(1.0, 0.55, 0.22): set = _set_torch_color
@export_range(0.0, 20.0, 0.1) var torch_energy: float = 5.0: set = _set_torch_energy
@export_range(1.0, 80.0, 0.5) var torch_range: float = 32.0: set = _set_torch_range
@export var torch_inset: float = 1.0: set = _set_torch_inset

@export_group("")
@export var rebuild_now: bool = false: set = _set_rebuild_now

var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _material: StandardMaterial3D = null
var _build_queued: bool = false

const _FEATURE_CHAMBER: int = 0
const _FEATURE_CHOKE: int = 1
# Each entry: { kind, y_center, r_horiz, r_vert, strength }
var _features: Array = []


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

	_generate_features()

	# Build vertex grid
	var positions := PackedVector3Array()
	positions.resize((ring_count + 1) * seg + 2)

	for r in range(ring_count + 1):
		var t: float = float(r) / float(ring_count)
		var y: float = top_y - t * height
		var bulge: float = sin(t * PI * bulge_frequency) * bulge_amplitude
		var profile_r: float = _profile_radius_at(y)
		for s in range(seg):
			var theta: float = float(s) / float(seg) * TAU
			var dx: float = cos(theta)
			var dz: float = sin(theta)
			# Sample 3D noise on the unit cylinder so the seam wraps seamlessly.
			var sample := Vector3(dx, y * inv_stretch, dz)
			var n_val: float = noise.get_noise_3dv(sample)
			var radius: float = profile_r + bulge + n_val * displacement
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

	# Top cap (normals point -Y, visible from below). Skipped when `open_top`
	# leaves the rim exposed to the sky, like a real sinkhole.
	if not open_top:
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
		_material.albedo_color = Color(1, 1, 1, 1)
		_material.albedo_texture = WALL_TEXTURE
		# Triplanar projects the texture from world XYZ planes, so it tiles
		# uniformly across the noise-displaced surface without per-vertex UVs.
		_material.uv1_triplanar = true
		_material.uv1_scale = Vector3(0.08, 0.08, 0.08)
		_material.roughness = 0.95
	# Render both sides — saves us debating winding, and means the wall stays
	# visible if the player ever pops out the open top and looks back in.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, _material)

	_mesh_instance.mesh = mesh
	_collision.shape = mesh.create_trimesh_shape()

	_build_torches(noise)


func _sample_wall_radius(noise: FastNoiseLite, t: float, theta: float) -> float:
	var inv_stretch: float = 1.0 / max(0.1, noise_vertical_stretch)
	var y: float = top_y - t * height
	var bulge: float = sin(t * PI * bulge_frequency) * bulge_amplitude
	var n_val: float = noise.get_noise_3dv(Vector3(cos(theta), y * inv_stretch, sin(theta)))
	return _profile_radius_at(y) + bulge + n_val * displacement


# Stratified deterministic placement of chambers and chokepoints along height.
# Each chamber owns a vertical slot and randomizes within it, so features stay
# evenly distributed even as counts change. Chokes use the same scheme but
# offset by half a slot so they tend to fall between chambers, giving the
# descent a chamber→squeeze→chamber rhythm.
func _generate_features() -> void:
	_features.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed * 7919 + 1

	var t_lo: float = 0.03
	var t_hi: float = 0.97
	var usable: float = t_hi - t_lo
	var bottom_y: float = top_y - height

	if chamber_count > 0:
		for i in range(chamber_count):
			var slot_lo: float = t_lo + usable * float(i) / float(chamber_count)
			var slot_hi: float = t_lo + usable * float(i + 1) / float(chamber_count)
			var t_c: float = lerp(slot_lo, slot_hi, rng.randf_range(0.15, 0.85))
			var y_c: float = top_y - t_c * height
			var extra: float = rng.randf_range(chamber_extra_radius_min, chamber_extra_radius_max)
			var r_h: float = base_radius + max(0.0, extra)
			var aspect: float = rng.randf_range(chamber_aspect_min, chamber_aspect_max)
			var r_v: float = r_h * aspect
			# Keep the chamber inside the chasm vertically so it doesn't break the caps.
			var max_v: float = min(y_c - bottom_y, top_y - y_c) - 4.0
			r_v = clamp(r_v, 8.0, max(8.0, max_v))
			_features.append({
				"kind": _FEATURE_CHAMBER, "y_center": y_c,
				"r_horiz": r_h, "r_vert": r_v, "strength": 0.0,
			})

	if chokepoint_count > 0:
		for i in range(chokepoint_count):
			# Half-slot offset so chokes sit between chambers rather than on top of them.
			var slot_lo: float = t_lo + usable * (float(i) + 0.5) / float(chokepoint_count)
			var slot_hi: float = t_lo + usable * (float(i) + 1.5) / float(chokepoint_count)
			slot_lo = min(slot_lo, t_hi)
			slot_hi = min(slot_hi, t_hi)
			var t_c: float = lerp(slot_lo, slot_hi, rng.randf_range(0.2, 0.8))
			var y_c: float = top_y - t_c * height
			var r_v: float = chokepoint_half_height * rng.randf_range(0.7, 1.4)
			var s: float = chokepoint_strength * rng.randf_range(0.75, 1.0)
			var max_v: float = min(y_c - bottom_y, top_y - y_c) - 2.0
			r_v = clamp(r_v, 2.0, max(2.0, max_v))
			_features.append({
				"kind": _FEATURE_CHOKE, "y_center": y_c,
				"r_horiz": 0.0, "r_vert": r_v, "strength": clamp(s, 0.0, 0.95),
			})


# Returns the profile-driven wall radius at world-y, before noise displacement.
# Chambers contribute via max(): each ellipsoid gives r(y) = R_h * sqrt(1-(dy/R_v)^2)
# inside its vertical extent, and the largest one wins. Chokepoints multiply
# the result by a smooth pinch bell. Outside any feature the profile is just
# the base radius, so the rim and far-from-feature regions match the original tube.
func _profile_radius_at(y: float) -> float:
	var r: float = base_radius
	var chamber_r: float = 0.0
	for f in _features:
		if f["kind"] == _FEATURE_CHAMBER:
			var dy: float = y - f["y_center"]
			var rv: float = f["r_vert"]
			if absf(dy) < rv:
				var k: float = dy / rv
				var local: float = f["r_horiz"] * sqrt(max(0.0, 1.0 - k * k))
				if local > chamber_r:
					chamber_r = local
	if chamber_r > r:
		r = chamber_r
	for f in _features:
		if f["kind"] == _FEATURE_CHOKE:
			var dy: float = y - f["y_center"]
			var rv: float = f["r_vert"]
			if absf(dy) < rv:
				var bell: float = cos(dy / rv * (PI * 0.5))
				bell *= bell
				r *= 1.0 - f["strength"] * bell
	return r


func _build_torches(noise: FastNoiseLite) -> void:
	var existing := get_node_or_null("Torches")
	if existing != null:
		existing.free()
	if torch_count <= 0:
		return

	var torches_root := Node3D.new()
	torches_root.name = "Torches"
	add_child(torches_root)

	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 8

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = torch_color
	glow_mat.emission_enabled = true
	glow_mat.emission = torch_color
	glow_mat.emission_energy_multiplier = 6.0
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed * 1009 + 7

	for i in range(torch_count):
		var t: float = (i + 0.5) / float(torch_count)
		var y: float = top_y - t * height
		# Alternate sides plus jitter so torches feel hand-placed.
		var theta: float = (PI if i % 2 == 1 else 0.0) + rng.randf_range(-0.9, 0.9) + i * 0.13
		var dx: float = cos(theta)
		var dz: float = sin(theta)
		var wall_r: float = _sample_wall_radius(noise, t, theta)
		var torch_r: float = max(0.5, wall_r - torch_inset)
		var pos := Vector3(dx * torch_r, y, dz * torch_r)

		var light := OmniLight3D.new()
		light.position = pos
		light.light_color = torch_color
		light.light_energy = torch_energy
		light.omni_range = torch_range
		light.omni_attenuation = 1.6
		torches_root.add_child(light)

		var glow := MeshInstance3D.new()
		glow.mesh = sphere
		glow.material_override = glow_mat
		glow.position = pos
		torches_root.add_child(glow)


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
func _set_open_top(v: bool) -> void: open_top = v; _queue_rebuild()
func _set_torch_count(v: int) -> void: torch_count = v; _queue_rebuild()
func _set_torch_color(v: Color) -> void: torch_color = v; _queue_rebuild()
func _set_torch_energy(v: float) -> void: torch_energy = v; _queue_rebuild()
func _set_torch_range(v: float) -> void: torch_range = v; _queue_rebuild()
func _set_torch_inset(v: float) -> void: torch_inset = v; _queue_rebuild()
func _set_chamber_count(v: int) -> void: chamber_count = v; _queue_rebuild()
func _set_chamber_extra_min(v: float) -> void: chamber_extra_radius_min = v; _queue_rebuild()
func _set_chamber_extra_max(v: float) -> void: chamber_extra_radius_max = v; _queue_rebuild()
func _set_chamber_aspect_min(v: float) -> void: chamber_aspect_min = v; _queue_rebuild()
func _set_chamber_aspect_max(v: float) -> void: chamber_aspect_max = v; _queue_rebuild()
func _set_chokepoint_count(v: int) -> void: chokepoint_count = v; _queue_rebuild()
func _set_chokepoint_strength(v: float) -> void: chokepoint_strength = v; _queue_rebuild()
func _set_chokepoint_half_height(v: float) -> void: chokepoint_half_height = v; _queue_rebuild()
func _set_rebuild_now(_v: bool) -> void:
	rebuild_now = false
	if is_inside_tree():
		_build()
