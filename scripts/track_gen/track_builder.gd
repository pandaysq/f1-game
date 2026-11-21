class_name TrackBuilder
extends RefCounted
## Builds the 3D track (mesh + collision) from TrackData at runtime.
## Surfaces expose grip via StaticBody3D metadata "grip" — the car reads it
## from raycast hits.

const GRASS_HALF_SIZE := 500.0
const KERB_WIDTH := 1.2
const KERB_HEIGHT := 0.06
const KERB_CURVATURE_THRESHOLD := 0.12  # rad between adjacent segments
const BARRIER_OFFSET := 10.0  # meters from road edge (runoff zone)
const BARRIER_HEIGHT := 1.0

const COLOR_ASPHALT := Color(0.16, 0.16, 0.17)
const COLOR_GRASS := Color(0.20, 0.42, 0.16)
const COLOR_KERB_RED := Color(0.78, 0.10, 0.10)
const COLOR_KERB_WHITE := Color(0.92, 0.92, 0.92)
const COLOR_BARRIER := Color(0.75, 0.75, 0.78)


## Builds the whole track under `parent` and returns the TrackRoot node.
static func build(track: TrackData, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "TrackRoot"
	root.set_meta("track", track)
	parent.add_child(root)

	var ground_y := _ground_level(track)
	_build_grass(root, track, ground_y)
	_build_road(root, track)
	_build_kerbs(root, track)
	_build_barriers(root, track, ground_y)
	_build_start_finish(root, track)
	return root


## Ground level below the lowest track point: grass plane, skirt and
## barrier base all sit there (track may dip below y=0 with elevation).
static func _ground_level(track: TrackData) -> float:
	var min_y := INF
	for p in track.points:
		min_y = minf(min_y, p.y)
	return min_y - 0.5


## Spawn transform for the player car at the track's spawn point.
static func spawn_transform(track: TrackData) -> Transform3D:
	var i := track.spawn_index
	var center := track.points[i]
	var dir := track.direction_at(i)
	var side := track.side_at(i)
	var origin := center + side * track.spawn_offset_lateral
	return Transform3D(alignment_basis(dir), origin + Vector3.UP * 0.6)


## Orthonormal car alignment on the track: forward (-Z column) along `dir`.
## A naive Basis(RIGHT, UP, -dir) is skewed whenever dir is not perpendicular
## to RIGHT, which twists the spawned car (uneven wheel loads, sideways creep).
static func alignment_basis(dir: Vector3) -> Basis:
	var z_axis := -dir.normalized()
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis)
	return Basis(x_axis, y_axis, z_axis)


# ------------------------------------------------------------------- spine


## Refined centerline used for ALL ribbon geometry (road, kerbs, skirt,
## barriers): sharp segments are subdivided so no quad can fold on itself.
## Phase-1 lesson: a 44-deg heading change over 2.3 m (Alpha Loop hairpin)
## self-intersects the inner quad edge, leaving phantom flaps and holes in
## the collision mesh. Subdivision is geometric only — TrackData, the
## racing line and progress tracking keep the original points.
## Returns [{c, s, w, angle, dist}] (center, side, half width, heading
## change to the NEXT refined segment [rad], distance along the spine).
static func _spine(track: TrackData, max_angle_rad: float = deg_to_rad(6.0)) -> Array:
	var n := track.point_count()
	var out: Array = []
	var dist := 0.0
	for i in range(n):
		var next_i := (i + 1) % n
		var c0: Vector3 = track.points[i]
		var c1: Vector3 = track.points[next_i]
		var seg := c1 - c0
		var seg_len := seg.length()
		if seg_len < 0.0001:
			continue
		# side/width/heading per original point (keeps banking tilt)
		var s0 := track.side_at(i)
		var w0 := track.widths[i] * 0.5
		var turn := track.direction_at(i).angle_to(track.direction_at(next_i))
		# subdivide so each refined segment turns at most max_angle_rad
		var steps := maxi(1, int(ceil(turn / max_angle_rad)))
		var curv := turn / seg_len
		for k in range(steps):
			var f := float(k) / float(steps)
			(
				out
				. append(
					{
						"c": c0.lerp(c1, f),
						"s": s0,
						"w": w0,
						"angle": turn / float(steps),
						"curv": curv,
						"dist": dist + seg_len * f,
					}
				)
			)
		dist += seg_len
	return out


# ---------------------------------------------------------------- road ribbon


static func _build_road(root: Node3D, track: TrackData) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var spine := _spine(track)
	var n := spine.size()
	for i in range(n):
		var a: Dictionary = spine[i]
		var b: Dictionary = spine[(i + 1) % n]
		var c0: Vector3 = a["c"]
		var c1: Vector3 = b["c"]
		var s0: Vector3 = a["s"]
		var s1: Vector3 = b["s"]
		var w0: float = a["w"]
		var w1: float = b["w"]
		var v0 := c0 - s0 * w0
		var v1 := c0 + s0 * w0
		var v2 := c1 - s1 * w1
		var v3 := c1 + s1 * w1
		var v_tile: float = a["dist"] / 8.0
		var v_tile_next: float = (a["dist"] + c0.distance_to(c1)) / 8.0
		# perimeter walk v0 -> v1 -> v3 -> v2; flip logic faces the road up
		_add_quad(
			st,
			v0,
			v1,
			v3,
			v2,
			Color.WHITE,
			Vector3.UP,
			Vector3.UP,
			[
				Vector2(0, v_tile),
				Vector2(1, v_tile),
				Vector2(1, v_tile_next),
				Vector2(0, v_tile_next)
			]
		)
	var mesh := st.commit()
	var body := _static_body_with_extruded_trimesh(mesh, 1.0, "asphalt", 0.35)
	root.add_child(_mesh_instance(mesh, COLOR_ASPHALT, 0.95))
	root.add_child(body)


# ------------------------------------------------------------------- kerbs


static func _build_kerbs(root: Node3D, track: TrackData) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var used := false

	var spine := _spine(track)
	var n := spine.size()
	for i in range(n):
		var a: Dictionary = spine[i]
		var kerb_color := COLOR_KERB_RED if int(a["dist"] / 3.0) % 2 == 0 else COLOR_KERB_WHITE
		# curvature threshold: the original rule (0.12 rad per original
		# segment ~ 9.5 m) expressed per meter, subdivision-invariant
		if float(a["curv"]) >= 0.0126:
			used = true
			_add_kerb_strip(st, spine, i, kerb_color)
	if not used:
		return
	var mesh := st.commit()
	root.add_child(_mesh_instance(mesh, Color.WHITE, 0.9, true))
	root.add_child(_static_body_with_extruded_trimesh(mesh, 0.95, "kerb", 0.12))


static func _add_kerb_strip(st: SurfaceTool, spine: Array, i: int, color: Color) -> void:
	var a: Dictionary = spine[i]
	var b: Dictionary = spine[(i + 1) % spine.size()]
	for side_sign: float in [-1.0, 1.0]:
		var s0: Vector3 = a["s"]
		var s1: Vector3 = b["s"]
		var w0: float = a["w"]
		var w1: float = b["w"]
		var c0: Vector3 = a["c"]
		var c1: Vector3 = b["c"]
		var inner0 := c0 + s0 * side_sign * w0
		var inner1 := c1 + s1 * side_sign * w1
		var outer0 := c0 + s0 * side_sign * (w0 + KERB_WIDTH) + Vector3.UP * KERB_HEIGHT
		var outer1 := c1 + s1 * side_sign * (w1 + KERB_WIDTH) + Vector3.UP * KERB_HEIGHT
		_add_quad(st, inner0, inner1, outer1, outer0, color, Vector3.UP, Vector3.UP)


# ---------------------------------------------------------------- barriers


static func _build_barriers(root: Node3D, track: TrackData, ground_y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine := _spine(track)
	var n := spine.size()
	for i in range(n):
		var a: Dictionary = spine[i]
		var b: Dictionary = spine[(i + 1) % n]
		for side_sign: float in [-1.0, 1.0]:
			var s0: Vector3 = a["s"]
			var s1: Vector3 = b["s"]
			var w0: float = a["w"] + BARRIER_OFFSET
			var w1: float = b["w"] + BARRIER_OFFSET
			var b0: Vector3 = a["c"] + s0 * side_sign * w0
			var b1: Vector3 = b["c"] + s1 * side_sign * w1
			# walls stand on the grass skirt edge (flat ground level)
			b0.y = ground_y
			b1.y = ground_y
			var top0 := b0 + Vector3.UP * BARRIER_HEIGHT
			var top1 := b1 + Vector3.UP * BARRIER_HEIGHT
			var outward := s0 * side_sign
			# one quad per side; flip logic makes each face its viewer
			_add_quad(st, b0, b1, top1, top0, COLOR_BARRIER, outward, outward)
			_add_quad(st, b1, b0, top0, top1, COLOR_BARRIER, -outward, -outward)
	var mesh := st.commit()
	root.add_child(_mesh_instance(mesh, COLOR_BARRIER, 0.6))
	root.add_child(_static_body_with_trimesh(mesh, 0.25, "barrier"))


# ------------------------------------------------------------ start/finish


static func _build_start_finish(root: Node3D, track: TrackData) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i := 0
	var next_i := 1
	var s0 := track.side_at(i)
	var s1 := track.side_at(next_i)
	var w0 := track.widths[i] * 0.5
	var w1 := track.widths[next_i] * 0.5
	var stripe_count := 12
	for k in range(stripe_count):
		var parity := k % 2
		var color := Color.BLACK if parity == 0 else Color.WHITE
		var f0 := -1.0 + 2.0 * k / stripe_count
		var f1 := -1.0 + 2.0 * (k + 1) / stripe_count
		var a := track.points[i] + s0 * w0 * f0 + Vector3.UP * 0.02
		var b := track.points[i] + s0 * w0 * f1 + Vector3.UP * 0.02
		var c := track.points[next_i] + s1 * w1 * f1 + Vector3.UP * 0.02
		var d := track.points[next_i] + s1 * w1 * f0 + Vector3.UP * 0.02
		_add_quad(st, a, b, c, d, color, Vector3.UP, Vector3.UP)
	var mesh := st.commit()
	root.add_child(_mesh_instance(mesh, Color.WHITE, 0.85, true))


# ------------------------------------------------------------------ helpers


static func _build_grass(root: Node3D, track: TrackData, ground_y: float) -> void:
	var skirt := _build_skirt_mesh(track, ground_y)

	var body := StaticBody3D.new()
	body.set_meta("grip", 0.55)
	body.set_meta("surface", "grass")
	var boundary := WorldBoundaryShape3D.new()
	boundary.plane = Plane(Vector3.UP, ground_y)
	var shape := CollisionShape3D.new()
	shape.shape = boundary
	body.add_child(shape)
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(skirt.get_faces())
	concave.backface_collision = true
	var skirt_shape := CollisionShape3D.new()
	skirt_shape.shape = concave
	body.add_child(skirt_shape)
	root.add_child(body)

	root.add_child(_mesh_instance(skirt, COLOR_GRASS, 1.0))

	var plane := PlaneMesh.new()
	plane.size = Vector2(GRASS_HALF_SIZE * 2.0, GRASS_HALF_SIZE * 2.0)
	var plane_instance := MeshInstance3D.new()
	plane_instance.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_GRASS
	mat.roughness = 1.0
	plane_instance.material_override = mat
	plane_instance.position.y = ground_y
	root.add_child(plane_instance)


## Runoff skirt: slopes from the road edge down to the ground plane, so the
## track can sit above or below y=0 (elevation) without buried geometry.
static func _build_skirt_mesh(track: TrackData, ground_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine := _spine(track)
	var n := spine.size()
	for i in range(n):
		var a: Dictionary = spine[i]
		var b: Dictionary = spine[(i + 1) % n]
		for side_sign: float in [-1.0, 1.0]:
			var s0: Vector3 = a["s"]
			var s1: Vector3 = b["s"]
			var w0: float = a["w"]
			var w1: float = b["w"]
			var inner0: Vector3 = a["c"] + s0 * side_sign * w0
			var inner1: Vector3 = b["c"] + s1 * side_sign * w1
			var outer0: Vector3 = a["c"] + s0 * side_sign * (w0 + BARRIER_OFFSET)
			var outer1: Vector3 = b["c"] + s1 * side_sign * (w1 + BARRIER_OFFSET)
			outer0.y = ground_y
			outer1.y = ground_y
			_add_quad(st, inner0, inner1, outer1, outer0, Color.WHITE)
	return st.commit()


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	color: Color,
	visible_from: Vector3 = Vector3.UP,
	normal_override: Variant = null,
	uvs: Array = [null, null, null, null]
) -> void:
	var corners := [a, b, c, d]
	var normal := (b - a).cross(c - a)
	if normal.length() > 0.000001:
		normal = normal.normalized()
		# Godot front faces use clockwise winding: a surface is visible from
		# the `visible_from` side when its right-hand-rule normal points AGAINST
		# that side. Flip the winding when the normal aligns with it instead.
	var flip := normal.dot(visible_from) > 0.0
	var face_normal := -normal if flip else normal
	if normal_override != null:
		face_normal = normal_override
	var triangle_orders := [[2, 1, 0], [3, 2, 1]] if flip else [[0, 1, 2], [1, 2, 3]]
	for order: Array in triangle_orders:
		for idx: int in order:
			st.set_color(color)
			st.set_normal(face_normal)
			if uvs[idx] != null:
				st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])


static func _mesh_instance(
	mesh: Mesh, albedo: Color, roughness: float, use_vertex_color: bool = false
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	if use_vertex_color:
		mat.vertex_color_use_as_albedo = true
	instance.material_override = mat
	return instance


## Closed-volume collision under a flat ribbon mesh: the flat surface is
## extruded `depth` meters down so a body that ends up below it resolves
## UP, not through. Zero-thickness trimeshes let cars tunnel at sharp
## corners (phase-2 lesson: the Alpha Loop hairpin).
static func _static_body_with_extruded_trimesh(
	mesh: Mesh, grip: float, surface_name: String, depth: float
) -> StaticBody3D:
	var faces := mesh.get_faces()
	var verts: PackedVector3Array = PackedVector3Array()
	var tri_count := faces.size() / 3
	for t in range(tri_count):
		var a: Vector3 = faces[t * 3]
		var b: Vector3 = faces[t * 3 + 1]
		var c: Vector3 = faces[t * 3 + 2]
		var a2 := a - Vector3.UP * depth
		var b2 := b - Vector3.UP * depth
		var c2 := c - Vector3.UP * depth
		# top + bottom
		verts.append(a)
		verts.append(b)
		verts.append(c)
		verts.append(a2)
		verts.append(b2)
		verts.append(c2)
		# side walls on each edge
		for edge in [[a, b, b2, a2], [b, c, c2, b2], [c, a, a2, c2]]:
			verts.append(edge[0])
			verts.append(edge[1])
			verts.append(edge[2])
			verts.append(edge[0])
			verts.append(edge[2])
			verts.append(edge[3])
	var body := StaticBody3D.new()
	body.set_meta("grip", grip)
	body.set_meta("surface", surface_name)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


static func _static_body_with_trimesh(
	mesh: Mesh, grip: float, surface_name: String
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("grip", grip)
	body.set_meta("surface", surface_name)
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	concave.backface_collision = true
	var shape := CollisionShape3D.new()
	shape.shape = concave
	body.add_child(shape)
	return body
