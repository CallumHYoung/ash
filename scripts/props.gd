extends Node3D

# Spawns GLB props into the world: scatters them across the surface above the
# chasm and threads an obstacle course down through the cavern. Each prop gets
# auto-generated trimesh collision per mesh, so the player can land on ledges,
# grapple to pillars, and crash into stalagmites just like the procedural
# platforms.

const GLB_DIR := "res://glb/"

# Global scale multiplier — actual GLB scales are unknown, so this is the
# single dial to use if every prop comes out too big or too small.
@export var scale_multiplier: float = 1.0

# Ledges are also valid checkpoints — landing on one mid-descent should save
# the player's progress. The other prop categories are decorative or grapple-
# only and don't need to count.
const CHECKPOINT_KINDS := ["ledge", "brokenbridge"]

# Each entry: [model_filename, position, y_rotation_deg, scale]
# Authored top-down: surface props first, then descending into the cavern.
const PLACEMENTS: Array = [
	# ---------- Surface (y ≈ 10) ----------
	# Rim landmarks framing the chasm — 3 cavemouths around its edge so the
	# pit feels like one of many entrances rather than the only opening.
	["cavemouth_01.glb", Vector3(118, 10, 70), 200.0, 1.0],
	["cavemouth_03.glb", Vector3(-130, 10, -40), 70.0, 1.0],
	["cavemouth_04.glb", Vector3(-50, 10, -135), 30.0, 1.0],

	# Arch the player can walk under between spawn and the NPC.
	["arch_02.glb", Vector3(0, 10, 160), 90.0, 1.2],
	["arch_05.glb", Vector3(40, 10, 100), 110.0, 1.0],

	# Boulders + rubble scattered on the surface.
	# Kept clear of the spawn→NPC→rim corridor along x≈0 from z=145 down to
	# z=110 — props in that lane were blocking the player from reaching the
	# NPC's interaction area.
	["boulder_01.glb", Vector3(-22, 10, 138), 25.0, 1.2],
	["boulder_03.glb", Vector3(28, 10, 142), 200.0, 1.0],
	["boulder_05.glb", Vector3(38, 10, 130), 60.0, 1.4],
	["boulder_02.glb", Vector3(-40, 10, 120), 280.0, 0.9],
	["boulder_04.glb", Vector3(-30, 10, 108), 145.0, 0.8],
	["rubble_01.glb", Vector3(-22, 10, 105), 15.0, 1.0],
	["rubble_02.glb", Vector3(25, 10, 105), 240.0, 1.1],
	["rubble_03.glb", Vector3(-28, 10, 150), 90.0, 1.0],
	["rubble_04.glb", Vector3(45, 10, 150), 0.0, 1.0],
	["rubble_05.glb", Vector3(-55, 10, 150), 180.0, 1.0],

	# Stalagmite cluster like petrified trees off to one side.
	["stalagmite_01.glb", Vector3(70, 10, 180), 0.0, 1.4],
	["stalagmite_02.glb", Vector3(78, 10, 175), 60.0, 1.6],
	["stalagmite_03.glb", Vector3(73, 10, 188), 130.0, 1.2],
	["stalagmite_04.glb", Vector3(82, 10, 184), 250.0, 1.5],
	["stalagmite_05.glb", Vector3(85, 10, 192), 30.0, 1.3],

	# Pillars giving the surface a ruined-temple silhouette.
	["pillar_01.glb", Vector3(-80, 10, 80), 0.0, 1.3],
	["pillar_02.glb", Vector3(-100, 10, 30), 0.0, 1.2],
	["pillar_03.glb", Vector3(-90, 10, -30), 0.0, 1.4],
	["pillar_04.glb", Vector3(60, 10, -90), 0.0, 1.2],
	["pillar_05.glb", Vector3(100, 10, -10), 0.0, 1.3],

	# A single spike cluster on the rim as a "danger ahead" signal — offset
	# from the spawn axis so the player can still walk straight to the edge.
	["spikecluster_03.glb", Vector3(20, 10, 112), 0.0, 1.0],

	# Far-edge stalagmites on the outskirts.
	["stalagmite_01.glb", Vector3(-180, 10, 60), 0.0, 1.5],
	["stalagmite_03.glb", Vector3(-200, 10, -60), 0.0, 1.3],
	["stalagmite_05.glb", Vector3(180, 10, 130), 0.0, 1.4],
	["stalagmite_02.glb", Vector3(200, 10, -50), 0.0, 1.6],

	# ---------- Cavern descent (y < 0) ----------
	# Strategy: hang stalactites from the rim region, place ledges as alt
	# grapple targets near the walls, span broken bridges across, and dress
	# existing platforms with stalagmites/rubble. Cavern radius ≈ 110, so we
	# keep props within radius ~95 to avoid clipping the wall.

	# Just below the rim — stalactites visible on the way in.
	["stalactite_01.glb", Vector3(40, 8, 60), 0.0, 1.2],
	["stalactite_02.glb", Vector3(-50, 7, -40), 0.0, 1.3],
	["stalactite_03.glb", Vector3(-30, 6, 70), 0.0, 1.4],
	["stalactite_04.glb", Vector3(70, 5, -30), 0.0, 1.2],

	# Tier 1 (near P1 at y=-10, P2 at y=-22): early grapple options.
	["ledge_01.glb", Vector3(35, -8, 25), 200.0, 1.4],
	["ledge_02.glb", Vector3(-30, -16, -15), 30.0, 1.4],
	["pillar_01.glb", Vector3(20, -25, 20), 0.0, 1.5],
	["stalagmite_02.glb", Vector3(-8, -9, 5), 0.0, 1.0],  # on/beside P1
	["rubble_03.glb", Vector3(8, -21, -3), 0.0, 1.0],     # on P2

	# Tier 2 (P3 y=-36, P4 y=-52): broken bridge as alt route.
	["brokenbridge_01.glb", Vector3(-15, -42, 0), 30.0, 1.4],
	["ledge_03.glb", Vector3(45, -45, -15), 130.0, 1.4],
	["stalactite_05.glb", Vector3(0, -28, 8), 0.0, 1.3],
	["stalagmite_03.glb", Vector3(-9, -51, -6), 0.0, 1.0],  # on P4

	# Tier 3 (P5 y=-70, P6 y=-88): arch milestone, hazard.
	["arch_01.glb", Vector3(0, -70, 0), 45.0, 1.5],
	["ledge_04.glb", Vector3(-40, -78, 30), 250.0, 1.5],
	["spikecluster_01.glb", Vector3(20, -88, 25), 0.0, 1.2],  # punish missed grapples
	["pillar_02.glb", Vector3(35, -82, -25), 0.0, 1.6],
	["boulder_03.glb", Vector3(7, -69, 7), 0.0, 0.8],     # on P5

	# Tier 4 (P7 y=-110, P8 y=-132): broken bridge + ledge fork.
	["brokenbridge_02.glb", Vector3(20, -118, -10), 75.0, 1.4],
	["ledge_05.glb", Vector3(-45, -125, -20), 50.0, 1.5],
	["stalactite_01.glb", Vector3(-25, -100, 35), 0.0, 1.4],
	["stalagmite_05.glb", Vector3(-4, -131, -7), 0.0, 1.0],  # on P8
	["spikecluster_04.glb", Vector3(40, -135, 5), 0.0, 1.2],

	# Tier 5 (P9 y=-158, P10 y=-188): pillar gauntlet.
	["pillar_03.glb", Vector3(-30, -170, 30), 0.0, 1.7],
	["pillar_04.glb", Vector3(40, -178, -25), 0.0, 1.7],
	["ledge_01.glb", Vector3(0, -175, -45), 0.0, 1.5],
	["arch_03.glb", Vector3(0, -188, 0), 90.0, 1.6],
	["stalactite_03.glb", Vector3(20, -148, 20), 0.0, 1.3],
	["rubble_05.glb", Vector3(5, -157, 8), 0.0, 1.0],     # on P9

	# Tier 6 (P11 y=-220, P12 y=-255): broken bridge crossing, more spikes.
	["brokenbridge_03.glb", Vector3(0, -235, 25), 0.0, 1.5],
	["brokenbridge_05.glb", Vector3(-30, -245, -10), 110.0, 1.4],
	["ledge_02.glb", Vector3(50, -240, 10), 200.0, 1.5],
	["spikecluster_05.glb", Vector3(-10, -260, 0), 0.0, 1.4],
	["stalactite_02.glb", Vector3(35, -210, -25), 0.0, 1.4],
	["stalactite_04.glb", Vector3(-35, -225, 25), 0.0, 1.3],

	# Below the last platform — unreachable hazard zone, pure dressing for
	# anyone peering further into the chasm.
	["spikecluster_02.glb", Vector3(0, -290, 0), 0.0, 1.6],
	["stalagmite_01.glb", Vector3(20, -295, 20), 0.0, 1.5],
	["stalagmite_04.glb", Vector3(-25, -305, -15), 0.0, 1.6],
	["pillar_05.glb", Vector3(40, -300, -10), 0.0, 1.8],
	["arch_04.glb", Vector3(0, -320, 0), 0.0, 2.0],
]


func _ready() -> void:
	for placement in PLACEMENTS:
		_spawn(placement[0], placement[1], placement[2], placement[3])


func _spawn(model: String, pos: Vector3, y_rot_deg: float, scl: float) -> void:
	var packed: PackedScene = load(GLB_DIR + model) as PackedScene
	if packed == null:
		push_warning("[Props] could not load " + model)
		return
	var inst: Node3D = packed.instantiate() as Node3D
	if inst == null:
		push_warning("[Props] " + model + " did not instantiate as Node3D")
		return
	inst.position = pos
	inst.rotation = Vector3(0, deg_to_rad(y_rot_deg), 0)
	inst.scale = Vector3.ONE * scl * scale_multiplier
	add_child(inst)
	var is_checkpoint := false
	for kind in CHECKPOINT_KINDS:
		if model.begins_with(kind):
			is_checkpoint = true
			break
	_add_collision(inst, is_checkpoint)


func _add_collision(node: Node, is_checkpoint: bool) -> void:
	# Walk the GLB tree, attaching a trimesh StaticBody3D under every
	# MeshInstance3D. Trimesh is overkill for boulders but it's the only
	# cheap way to get accurate collision on procedural-looking assets
	# without authoring shapes by hand.
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.create_trimesh_collision()
		if is_checkpoint:
			# create_trimesh_collision spawns a StaticBody3D child named
			# "<MeshName>_col". Tag it so the player's checkpoint logic picks
			# it up when landed on.
			for child in mi.get_children():
				if child is StaticBody3D:
					child.add_to_group("checkpoint")
	for child in node.get_children():
		_add_collision(child, is_checkpoint)
