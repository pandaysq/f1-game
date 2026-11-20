class_name TrackValidator
extends RefCounted
## Validation rules for track data (see tracks/README.md).
## Used by tracks/validate_tracks.gd (CI) and tests/run_tests.gd.


## Validate a parsed TrackData. Returns array of problem descriptions
## (empty array = valid).
static func validate(track: TrackData) -> Array[String]:
	var problems: Array[String] = []
	var n := track.point_count()

	if track.track_name.strip_edges() == "":
		problems.append("name is empty")
	if not track.closed:
		problems.append("track is not closed")
	if n < 8:
		problems.append("centerline has less than 8 points")

	for i in range(n):
		if not _is_finite_vec(track.points[i]):
			problems.append("point %d has non-finite coordinates" % i)
		if track.widths[i] <= 3.0:
			problems.append("point %d: width %.1f <= 3.0 m" % [i, track.widths[i]])
		elif not is_finite(track.widths[i]):
			problems.append("point %d: width is not finite" % i)
		if not is_finite(track.banking[i]):
			problems.append("point %d: banking is not finite" % i)

	if n >= 2:
		problems.append_array(_self_intersection_problems(track))

	if not track.has_meta("skip_timing_check"):
		problems.append_array(_timing_problems(track))

	if track.spawn_index < 0 or track.spawn_index >= n:
		problems.append("spawn point_index %d out of range" % track.spawn_index)

	return problems


static func _timing_problems(track: TrackData) -> Array[String]:
	var problems: Array[String] = []
	var n := track.point_count()
	var has_start_finish := false
	for line in track.timing_lines:
		var idx := int(line.get("index", -1))
		if idx < 0 or idx >= n:
			problems.append(
				"timing line '%s': index %d out of range" % [str(line.get("name", "?")), idx]
			)
		if str(line.get("name", "")) == "start_finish":
			has_start_finish = true
	if n > 0 and not has_start_finish:
		problems.append("no start_finish timing line")
	return problems


static func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## Segment-segment intersection on the 2D (XZ) projection, skipping segments
## that share an endpoint (adjacent in a closed loop).
static func _self_intersection_problems(track: TrackData) -> Array[String]:
	var problems: Array[String] = []
	var n := track.point_count()
	for i in range(n):
		var a := _xz(track.points[i])
		var b := _xz(track.points[(i + 1) % n])
		for j in range(i + 2, n):
			# segments adjacent in a closed loop share a vertex
			if i == 0 and j == n - 1:
				continue
			var c := _xz(track.points[j])
			var d := _xz(track.points[(j + 1) % n])
			if _segments_intersect(a, b, c, d):
				problems.append(
					"self-intersection: segments %d-%d and %d-%d" % [i, i + 1, j, j + 1]
				)
				return problems  # one report is enough
	return problems


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _orientation(p: Vector2, q: Vector2, r: Vector2) -> int:
	var val := (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
	if absf(val) < 0.000001:
		return 0  # collinear
	return 1 if val > 0.0 else 2


static func _segments_intersect(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> bool:
	var o1 := _orientation(p1, q1, p2)
	var o2 := _orientation(p1, q1, q2)
	var o3 := _orientation(p2, q2, p1)
	var o4 := _orientation(p2, q2, q1)
	return o1 != o2 and o3 != o4
