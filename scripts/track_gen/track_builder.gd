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

	_build_grass(root)
	_build_road(root, track)
	_build_kerbs(root, track)
	_build_barriers(root, track)
	_build_start_finish(root, track)
	return root


## Spawn transform for the player car at the track's spawn point.
static func spawn_transform(track: TrackData) -> Transform3D:
	var i := track.spawn_index
	var center := track.points[i]
	var dir := track.direction_at(i)
	var side := track.side_at(i)
	var origin := center + side * track.spawn_offset_lateral
	# Basis(x_axis, y_axis, z_axis): car forward is -Z, so z_axis = -dir
	var basis := Basis(Vector3.RIGHT, Vector3.UP, -dir)
	return Transform3D(basis, origin + Vector3.UP * 0.6)


# ---------------------------------------------------------------- road ribbon


static func _build_road(root: Node3D, track: TrackData) -> void:
	var n := track.point_count()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var distance := 0.0
	for i in range(n):
		var next_i := (i + 1) % n
		var c0 := track.points[i]
		var c1 := track.points[next_i]
		var s0 := track.side_at(i)
		var s1 := track.side_at(next_i)
		var w0 := track.widths[i] * 0.5
		var w1 := track.widths[next_i] * 0.5
		var v0 := c0 - s0 * w0
		var v1 := c0 + s0 * w0
		var v2 := c1 - s1 * w1
		var v3 := c1 + s1 * w1
		var v_tile := distance / 8.0
		var v_tile_next := (distance + c0.distance_to(c1)) / 8.0

		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, v_tile))
		st.add_vertex(v0)
		st.set_uv(Vector2(1, v_tile))
		st.add_vertex(v1)
		st.set_uv(Vector2(0, v_tile_next))
		st.add_vertex(v2)
		st.set_uv(Vector2(1, v_tile))
		st.add_vertex(v1)
		st.set_uv(Vector2(1, v_tile_next))
		st.add_vertex(v3)
		st.set_uv(Vector2(0, v_tile_next))
		st.add_vertex(v2)
		distance += c0.distance_to(c1)

	var mesh := st.commit()
	var body := _static_body_with_trimesh(mesh, 1.0, "asphalt")
	root.add_child(_mesh_instance(mesh, COLOR_ASPHALT, 0.95))
	root.add_child(body)


# ------------------------------------------------------------------- kerbs


static func _build_kerbs(root: Node3D, track: TrackData) -> void:
	var n := track.point_count()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var used := false
	var distance := 0.0

	for i in range(n):
		var next_i := (i + 1) % n
		var seg_length := track.points[i].distance_to(track.points[next_i])
		var angle := track.direction_at(i).angle_to(track.direction_at(next_i))
		var parity := int(distance / 3.0) % 2
		var kerb_color := COLOR_KERB_RED if parity == 0 else COLOR_KERB_WHITE
		if angle >= KERB_CURVATURE_THRESHOLD:
			used = true
			_add_kerb_strip(st, track, i, kerb_color)
		distance += seg_length

	if not used:
		return
	var mesh := st.commit()
	root.add_child(_mesh_instance(mesh, Color.WHITE, 0.9, true))
	root.add_child(_static_body_with_trimesh(mesh, 0.95, "kerb"))


static func _add_kerb_strip(st: SurfaceTool, track: TrackData, i: int, color: Color) -> void:
	var next_i := (i + 1) % track.point_count()
	for side_sign: float in [-1.0, 1.0]:
		var s0 := track.side_at(i)
		var s1 := track.side_at(next_i)
		var w0 := track.widths[i] * 0.5
		var w1 := track.widths[next_i] * 0.5
		var inner0 := track.points[i] + s0 * side_sign * w0
		var inner1 := track.points[next_i] + s1 * side_sign * w1
		var outer0 := (
			track.points[i] + s0 * side_sign * (w0 + KERB_WIDTH) + Vector3.UP * KERB_HEIGHT
		)
		var outer1 := (
			track.points[next_i] + s1 * side_sign * (w1 + KERB_WIDTH) + Vector3.UP * KERB_HEIGHT
		)
		_add_quad(st, inner0, inner1, outer0, outer1, color)


# ---------------------------------------------------------------- barriers


static func _build_barriers(root: Node3D, track: TrackData) -> void:
	var n := track.point_count()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var next_i := (i + 1) % n
		for side_sign: float in [-1.0, 1.0]:
			var s0 := track.side_at(i)
			var s1 := track.side_at(next_i)
			var w0 := track.widths[i] * 0.5 + BARRIER_OFFSET
			var w1 := track.widths[next_i] * 0.5 + BARRIER_OFFSET
			var base0 := track.points[i] + s0 * side_sign * w0
			var base1 := track.points[next_i] + s1 * side_sign * w1
			var top0 := base0 + Vector3.UP * BARRIER_HEIGHT
			var top1 := base1 + Vector3.UP * BARRIER_HEIGHT
			# double-sided quad (wall has collision and visual from both sides)
			_add_quad(st, base0, base1, top0, top1, COLOR_BARRIER)
			_add_quad(st, base1, base0, top1, top0, COLOR_BARRIER)
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
		_add_quad(st, a, b, c, d, color)
	var mesh := st.commit()
	root.add_child(_mesh_instance(mesh, Color.WHITE, 0.85, true))


# ------------------------------------------------------------------ helpers


static func _build_grass(root: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GRASS_HALF_SIZE * 2.0, GRASS_HALF_SIZE * 2.0)
	var body := StaticBody3D.new()
	body.set_meta("grip", 0.55)
	body.set_meta("surface", "grass")
	var boundary := WorldBoundaryShape3D.new()
	boundary.plane = Plane(Vector3.UP, 0.0)
	var shape := CollisionShape3D.new()
	shape.shape = boundary
	body.add_child(shape)
	root.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_GRASS
	mat.roughness = 1.0
	mesh_instance.material_override = mat
	mesh_instance.position.y = -0.05
	root.add_child(mesh_instance)


static func _add_quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color
) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length() > 0.000001:
		normal = normal.normalized()
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(d)


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


static func _static_body_with_trimesh(
	mesh: Mesh, grip: float, surface_name: String
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("grip", grip)
	body.set_meta("surface", surface_name)
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	var shape := CollisionShape3D.new()
	shape.shape = concave
	body.add_child(shape)
	return body
