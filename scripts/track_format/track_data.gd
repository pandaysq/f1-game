class_name TrackData
extends RefCounted
## Parsed track file (tracks/*.json). Plain data holder used by the builder,
## the timing system and the tests. See tracks/README.md for the format.

var track_name: String = ""
var closed: bool = false
var points: Array[Vector3] = []
var widths: Array[float] = []
var banking: Array[float] = []
var surfaces: Dictionary = {}  # name -> {grip: float}
var timing_lines: Array[Dictionary] = []  # {name, index}
var spawn_index: int = 0
var spawn_offset_lateral: float = 0.0
var source_path: String = ""


## Parse a track JSON string. Returns null on structural errors (see message).
static func parse(text: String, source_path: String = "") -> TrackData:
	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("TrackData: invalid JSON in %s" % source_path)
		return null
	var d: Dictionary = data
	var track := TrackData.new()
	track.source_path = source_path
	track.track_name = str(d.get("name", "unnamed"))
	track.closed = bool(d.get("closed", false))

	var centerline: Variant = d.get("centerline", [])
	if not (centerline is Array) or (centerline as Array).size() < 8:
		push_error("TrackData: centerline must be an array with >= 8 points")
		return null
	for point_v: Variant in centerline:
		if not (point_v is Dictionary):
			push_error("TrackData: centerline point is not an object")
			return null
		var p: Dictionary = point_v
		var pos := Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
		track.points.append(pos)
		track.widths.append(float(p.get("width", 10.0)))
		track.banking.append(deg_to_rad(float(p.get("banking_deg", 0.0))))

	for s_name: String in d.get("surfaces", {}) as Dictionary:
		var s_def: Variant = (d.get("surfaces", {}) as Dictionary)[s_name]
		track.surfaces[s_name] = float((s_def as Dictionary).get("grip", 1.0))

	for line_v: Variant in d.get("timing_lines", []):
		track.timing_lines.append(line_v as Dictionary)

	var spawn: Dictionary = d.get("spawn", {})
	track.spawn_index = int(spawn.get("point_index", 0))
	track.spawn_offset_lateral = float(spawn.get("offset_lateral", 0.0))
	return track


## Load and parse a track file from res:// path. Returns null on failure.
static func load_from(path: String) -> TrackData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("TrackData: cannot read %s" % path)
		return null
	return TrackData.parse(text, path)


## Number of centerline points.
func point_count() -> int:
	return points.size()


## Tangent direction at point i (normalized, wraps around closed loops).
func direction_at(i: int) -> Vector3:
	var n := point_count()
	var prev := points[(i - 1 + n) % n]
	var next := points[(i + 1) % n]
	var dir := next - prev
	return dir.normalized() if dir.length() > 0.0001 else Vector3.FORWARD


## Lateral (right-hand) unit vector at point i, including banking tilt.
func side_at(i: int) -> Vector3:
	var dir := direction_at(i)
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.0001:
		return Vector3.RIGHT
	side = side.normalized()
	if banking[i] != 0.0:
		side = side.rotated(dir, banking[i])
	return side


## Approximate lap length in meters (closed loops only).
func lap_length() -> float:
	var length := 0.0
	var n := point_count()
	for i in range(n):
		length += points[i].distance_to(points[(i + 1) % n])
	return length
