class_name RaceSession
extends RefCounted
## Offline race session (Phase 2): grid start, per-car lap counting and
## positions, DRS availability rules, aero wake (dirty air / slipstream)
## computation, finish classification. Pure logic — fed car states each
## physics tick, so it is unit-testable without a running scene.

signal lap_completed(car_index: int, lap_time: float)
signal race_finished(classification: Array)

const TICK_DT := 1.0 / 120.0

var track: TrackData
var config: Dictionary = {}
var car_count := 0
var total_laps := 5
var race_time: float = 0.0
var started := false  # green flag

var progress: Array[float] = []  # 0..1 around the lap
var speeds: Array[float] = []  # last fed speed per car (m/s) — interval timing
var laps_completed: Array[int] = []
var laps_started: Array[bool] = []  # crossed the line since the grid
var lap_start_time: Array[float] = []
var last_lap_time: Array[float] = []
var best_lap_time: Array[float] = []
var finished: Array[bool] = []
var finish_time: Array[float] = []
var classification: Array = []
var _max_progress_since_line: Array[float] = []
var _last_positions: Array = []
var _wake_df: Array[float] = []
var _wake_drag: Array[float] = []
var _drs_zone: Array[bool] = []
var _drs_available: Array[bool] = []
var _cars_ahead: Array[int] = []  # nearest car ahead on track, -1 none
var _progress_hint: Array[int] = []  # last known centerline index per car (audit A1)


func _init(p_track: TrackData, p_config: Dictionary, p_car_count: int) -> void:
	track = p_track
	config = p_config
	car_count = p_car_count
	total_laps = maxf(int(p_config.get("laps", 5)), 1)
	progress.resize(car_count)
	progress.fill(-1.0)
	laps_completed.resize(car_count)
	laps_completed.fill(0)
	laps_started.resize(car_count)
	laps_started.fill(false)
	lap_start_time.resize(car_count)
	lap_start_time.fill(0.0)
	last_lap_time.resize(car_count)
	last_lap_time.fill(-1.0)
	best_lap_time.resize(car_count)
	best_lap_time.fill(-1.0)
	finished.resize(car_count)
	finished.fill(false)
	finish_time.resize(car_count)
	finish_time.fill(-1.0)
	_max_progress_since_line.resize(car_count)
	_max_progress_since_line.fill(0.0)
	_wake_df.resize(car_count)
	_wake_df.fill(0.0)
	_wake_drag.resize(car_count)
	_wake_drag.fill(0.0)
	_drs_zone.resize(car_count)
	_drs_zone.fill(false)
	_drs_available.resize(car_count)
	_drs_available.fill(false)
	_cars_ahead.resize(car_count)
	_cars_ahead.fill(-1)
	speeds.resize(car_count)
	speeds.fill(0.0)
	_progress_hint.resize(car_count)
	_progress_hint.fill(-1)


## Grid transforms: two-wide rows behind the start line, 8 m per row,
## pole on the right column nearest the line. Cars face along the track.
## The grid is anchored to the START/FINISH LINE (not the spawn point):
## slots must sit BEHIND the line so the first crossing arms lap 1.
func grid_transforms() -> Array[Transform3D]:
	var row_gap := 8.0
	var lateral := 2.6
	var out: Array[Transform3D] = []
	var i := _start_line_index()
	var center: Vector3 = track.points[i]
	var authored_basis := TrackBuilder.alignment_basis(track.direction_at(i))
	for car in range(car_count):
		if car < track.grid_slots.size():
			out.append(Transform3D(authored_basis, track.grid_slots[car] + Vector3.UP * 0.6))
			continue
		var row := car / 2
		var dist := row_gap * float(row + 1)
		var back := center - track.direction_at(i) * dist
		var side_sign := -1.0 if car % 2 == 0 else 1.0
		var side := track.side_at(i)
		var pos := back + side * side_sign * lateral
		var heading := track.direction_at(_index_behind(i, int(dist / 10.0) + 1))
		out.append(Transform3D(TrackBuilder.alignment_basis(heading), pos + Vector3.UP * 0.6))
	return out


func _index_behind(i: int, steps: int) -> int:
	var n := track.point_count()
	return (i - steps + n * 8) % n


## Index of the start/finish timing line (fallback: 0).
func _start_line_index() -> int:
	for line in track.timing_lines:
		if str(line.get("name", "")) == "start_finish":
			return clampi(int(line.get("index", 0)), 0, track.point_count() - 1)
	return 0


## Start the race (green flag). Called after the countdown.
func start_race() -> void:
	started = true
	race_time = 0.0


## Per-tick update. car_states: Array of {pos: Vector3, forward: Vector3,
## speed: float} in car order.
func update(car_states: Array, delta: float) -> void:
	if car_states.is_empty():
		return
	if not started:
		return
	race_time += delta
	var count := mini(car_count, car_states.size())
	for i in range(count):
		var state: Dictionary = car_states[i]
		_track_car(i, state.get("pos", Vector3.ZERO) as Vector3, delta)
		speeds[i] = float(state.get("speed", 0.0))
	_update_wakes(car_states)
	_update_ahead()
	_update_drs(car_states)
	if not classification.is_empty():
		return
	var all_done := true
	for i in range(car_count):
		if finished[i]:
			continue
		if laps_completed[i] >= total_laps:
			finished[i] = true
			finish_time[i] = race_time
		else:
			all_done = false
	if all_done and classification.is_empty():
		_classify()
		race_finished.emit(classification)


func _track_car(i: int, pos: Vector3, _delta: float) -> void:
	if finished[i]:
		return
	var p := _progress_of(pos, i)
	if progress[i] < 0.0:
		progress[i] = p
		_max_progress_since_line[i] = p
		return
	var prev := progress[i]
	_max_progress_since_line[i] = maxf(_max_progress_since_line[i], p)
	# crossing the start line forward
	if prev > 0.9 and p < 0.1 and _max_progress_since_line[i] > 0.6:
		if not laps_started[i]:
			laps_started[i] = true
			lap_start_time[i] = race_time
			_max_progress_since_line[i] = 0.0
		else:
			var lap_time := race_time - lap_start_time[i]
			last_lap_time[i] = lap_time
			if best_lap_time[i] < 0.0 or lap_time < best_lap_time[i]:
				best_lap_time[i] = lap_time
			laps_completed[i] += 1
			lap_start_time[i] = race_time
			_max_progress_since_line[i] = 0.0
			lap_completed.emit(i, lap_time)
	progress[i] = p


## Nearest centerline fraction with a windowed search around the car's
## last known index (audit A1: the per-car full scan every physics tick
## was the hottest CPU spot on a full grid). First call and teleports
## (window miss over 20 m) fall back to a full scan.
func _progress_of(pos: Vector3, car: int) -> float:
	var n := track.point_count()
	var hint := -1
	if car >= 0 and car < _progress_hint.size():
		hint = _progress_hint[car]
	if hint < 0:
		var found := _full_scan_index(pos)
		_set_progress_hint(car, found)
		return float(found) / float(n)
	var best := hint
	var best_d := INF
	for offset in range(-24, 25):
		var idx := (hint + offset + n) % n
		var d: float = track.points[idx].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = idx
	if best_d > 400.0:
		best = _full_scan_index(pos)
	_set_progress_hint(car, best)
	return float(best) / float(n)


## Brute-force nearest centerline index — the windowed search's fallback
## and the first-call initializer.
func _full_scan_index(pos: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in range(track.point_count()):
		var d: float = track.points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _set_progress_hint(car: int, index: int) -> void:
	if car >= 0 and car < _progress_hint.size():
		_progress_hint[car] = index


## Dirty air / slipstream wake per car from geometric proximity.
func _update_wakes(car_states: Array) -> void:
	var vehicle: Dictionary = _vehicle_data()
	var wake: Dictionary = vehicle.get("aero", {}).get("wake", {})
	var dirty_m := float(wake.get("dirty_air_distance_m", 12.0))
	var slip_m := float(wake.get("slipstream_distance_m", 25.0))
	var window_m := float(wake.get("lateral_window_m", 3.5))
	var count := mini(car_count, car_states.size())
	for i in range(count):
		_wake_df[i] = 0.0
		_wake_drag[i] = 0.0
		var me: Dictionary = car_states[i]
		var pos_i: Vector3 = me.get("pos", Vector3.ZERO)
		var fwd_i: Vector3 = me.get("forward", Vector3.FORWARD)
		for j in range(car_count):
			if i == j:
				continue
			var other: Dictionary = car_states[j]
			var offset: Vector3 = (other.get("pos", Vector3.ZERO) as Vector3) - pos_i
			var along := offset.dot(fwd_i)
			if along <= 0.0:
				continue
			var lateral := (offset - fwd_i * along).length()
			if lateral > window_m:
				continue
			var f := 1.0 - clampf((along - 0.0) / slip_m, 0.0, 1.0)
			_wake_drag[i] = maxf(_wake_drag[i], f)
			var f_dirty := 1.0 - clampf((along - 0.0) / dirty_m, 0.0, 1.0)
			_wake_df[i] = maxf(_wake_df[i], f_dirty)


## DRS rules: enabled + in a zone + above min speed + within gap_s of the
## car ahead on track. Availability per car, activation is the driver's.
func _update_drs(car_states: Array) -> void:
	var drs: Dictionary = config.get("drs", {})
	var enabled := bool(drs.get("enabled", false))
	var min_speed := float(drs.get("min_speed_mps", 60.0))
	var gap_s := float(drs.get("gap_to_car_ahead_s", 1.0))
	var n := track.point_count()
	var count := mini(car_count, car_states.size())
	for i in range(count):
		_drs_zone[i] = false
		_drs_available[i] = false
		if not enabled or finished[i]:
			continue
		var me: Dictionary = car_states[i]
		var speed := float(me.get("speed", 0.0))
		if speed < min_speed:
			continue
		var p := progress[i]
		if p < 0.0:
			continue
		var in_zone := false
		for zone in track.drs_zones:
			var a := float(int(zone.get("start_index", 0))) / float(n)
			var b := float(int(zone.get("end_index", 0))) / float(n)
			if p >= a and p <= b:
				in_zone = true
				break
		_drs_zone[i] = in_zone
		if not in_zone:
			continue
		# gap to the car ahead along the track
		var ahead := _cars_ahead[i]
		if ahead < 0:
			continue
		var dist := _distance_ahead(ahead, i)
		var gap := dist / maxf(speed, 5.0)
		_drs_available[i] = gap <= gap_s


## Distance along the lap from car i to car ahead (forward, wraps).
## Purely geometric (audit C1): completed laps must not enter — a car a
## lap up that just passed us IS physically where it looks, and the old
## lap-adjusted delta used to clamp to 0 m and fake DRS availability.
## Lap-aware race distances (intervals, laps behind) use _race_distance().
func _distance_ahead(ahead: int, i: int) -> float:
	var lap_len := track.lap_length()
	var delta := progress[ahead] - progress[i]
	if delta < 0.0:
		delta += 1.0
	return clampf(delta, 0.0, 1.0) * lap_len


## Live interval to the car directly ahead in race order, seconds (0.10.0
## tower). The race leader and single-car sessions return 0. Both finished:
## exact finish-time delta; otherwise distance over the follower's speed
## (same estimate the DRS gap uses).
func interval_ahead_s(rank: int) -> float:
	var order := positions()
	if rank <= 0 or rank >= order.size():
		return 0.0
	var i: int = order[rank]
	var ahead: int = order[rank - 1]
	if finished[i] and finished[ahead]:
		return maxf(finish_time[i] - finish_time[ahead], 0.0)
	var dist_m := _race_distance(ahead) - _race_distance(i)
	return maxf(dist_m, 0.0) / maxf(float(speeds[i]), 5.0)


## Continuous race distance (completed laps + current progress) in meters —
## the interval clock's yardstick. Unlike the raw progress delta it does
## not wrap when a car crosses the start/finish line mid-pack.
func _race_distance(i: int) -> float:
	return (float(laps_completed[i]) + clampf(progress[i], 0.0, 1.0)) * track.lap_length()


## Full laps car i trails the race leader (0 = on the lead lap). Distance
## based (continuous race distance / lap length): a crossing-count diff
## flickers — while the leader's lap fraction is below the follower's it
## reads one lap more than reality (bounty-hunt fix, 0.10.0).
func laps_behind(i: int) -> int:
	var order := positions()
	if order.is_empty():
		return 0
	var gap_m := _race_distance(order[0]) - _race_distance(i)
	return maxi(0, int(floor(gap_m / track.lap_length())))


func _update_ahead() -> void:
	var count := mini(car_count, progress.size())
	for i in range(count):
		_cars_ahead[i] = -1
		var best_dist := INF
		for j in range(car_count):
			if i == j:
				continue
			var dist := _distance_ahead(j, i)
			if dist < best_dist and dist < 40.0:
				best_dist = dist
				_cars_ahead[i] = j


## Current race order: finished cars by finish time, then laps desc,
## then progress desc.
func positions() -> Array[int]:
	var order: Array[int] = []
	for i in range(car_count):
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			if finished[a] != finished[b]:
				return finished[a]
			if finished[a] and finished[b]:
				return finish_time[a] < finish_time[b]
			if laps_completed[a] != laps_completed[b]:
				return laps_completed[a] > laps_completed[b]
			return progress[a] > progress[b]
	)
	return order


func position_of(car_index: int) -> int:
	var order := positions()
	return order.find(car_index) + 1


## Final classification (race over): array of dicts in finish order.
func _classify() -> void:
	var order := positions()
	classification = []
	for rank in range(order.size()):
		var i: int = order[rank]
		(
			classification
			. append(
				{
					"position": rank + 1,
					"car_index": i,
					"laps": laps_completed[i],
					"best_lap": best_lap_time[i],
					"finish_time": finish_time[i],
				}
			)
		)


func _vehicle_data() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## Aero context for car i (set onto Car.aero_wake_df / aero_wake_drag).
func wake_df(i: int) -> float:
	return _wake_df[i]


func wake_drag(i: int) -> float:
	return _wake_drag[i]


func drs_available(i: int) -> bool:
	return _drs_available[i]


func drs_in_zone(i: int) -> bool:
	return _drs_zone[i]
