class_name RacingLine
extends RefCounted
## AI racing line (Phase 2): centerline with apex-cutting lateral offsets,
## smoothed so entries/exits blend. Pure data, deterministic: same track ->
## same line. See docs/PHYSICS.md and docs/ARCHITECTURE.md.

var points: Array[Vector3] = []  # center + side * offset
var offsets: Array[float] = []  # lateral offset [m], + = right of travel
var curvature: Array[float] = []  # signed [rad/m], + = left turn (see below)
var lengths: Array[float] = []  # distance to the next line point [m]


## Build the racing line from a track.
## margin_m: kerb-side safety margin; strength 0..1: how much of the usable
## width the line uses at the reference curvature; smooth_window: odd-ish
## moving-average width in points.
static func build(
	track: TrackData, margin_m: float = 2.0, strength: float = 0.9, smooth_window: int = 9
) -> RacingLine:
	var n := track.point_count()
	var line := RacingLine.new()
	line.curvature = _curvature(track.points)
	line.offsets.resize(n)
	line.offsets.fill(0.0)

	# reference curvature: at this turn radius the line uses full strength
	var k_ref := 1.0 / 40.0
	var raw: Array[float] = []
	raw.resize(n)
	for i in range(n):
		var usable := track.widths[i] * 0.5 - margin_m
		usable = maxf(usable, 0.0)
		# positive curvature = left turn -> apex is to the LEFT -> negative offset
		raw[i] = clampf(-line.curvature[i] / k_ref * strength, -usable, usable)
	line.offsets = _smooth_wrapped(raw, maxi(smooth_window, 1))

	for i in range(n):
		var side := track.side_at(i)
		line.points.append(track.points[i] + side * line.offsets[i])
	for i in range(n):
		line.lengths.append(line.points[i].distance_to(line.points[(i + 1) % n]))
	return line


## Signed curvature per point [rad/m]: + = track turns left when driving
## forward. Computed in the XZ plane from the centerline tangents.
static func _curvature(points: Array[Vector3]) -> Array[float]:
	var n := points.size()
	var out: Array[float] = []
	out.resize(n)
	for i in range(n):
		var d1 := _xz(points[(i - 1 + n) % n], points[i])
		var d2 := _xz(points[i], points[(i + 1) % n])
		var ds := (d1.length() + d2.length()) * 0.5
		if ds < 0.0001:
			out[i] = 0.0
			continue
		var d1n := d1.normalized()
		var d2n := d2.normalized()
		var cross_y := d1n.z * d2n.x - d1n.x * d2n.z
		var angle := atan2(cross_y, d1n.dot(d2n))
		out[i] = angle / ds
	return out


static func _xz(a: Vector3, b: Vector3) -> Vector3:
	var d := b - a
	d.y = 0.0
	return d


## Wrapped moving average of offsets (keeps the loop closed).
static func _smooth_wrapped(values: Array[float], window: int) -> Array[float]:
	var n := values.size()
	var half := window / 2
	var out: Array[float] = []
	out.resize(n)
	for i in range(n):
		var acc := 0.0
		for k in range(-half, half + 1):
			acc += values[(i + k + n) % n]
		out[i] = acc / float(2 * half + 1)
	return out


## Total length of the line [m].
func length() -> float:
	var total := 0.0
	for l in lengths:
		total += l
	return total


## Arc-length distance from point a to point b along the line (forward,
## wrapped). Both indices must be valid; returns value in [0, length).
func distance_between(a: int, b: int) -> float:
	var n := points.size()
	var dist := 0.0
	var i := a
	while i != b:
		dist += lengths[i % n]
		i = (i + 1) % n
		if dist > length():
			break
	return fmod(dist, length())
