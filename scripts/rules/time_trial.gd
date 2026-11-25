class_name TimeTrial
extends RefCounted
## Time Trial session: lap counting, sector splits, best lap persistence.
## Progress tracking is projection-based (nearest centerline point), so it
## works without physical timing-line nodes and is unit-testable directly.
##
## A lap is counted when progress wraps past the start line AND the car has
## reached the last sector threshold during that lap (prevents counting
## back-and-forth crossings).

signal lap_completed(lap_time_s: float, is_best: bool)
signal sector_completed(sector: int, time_s: float, is_best: bool)

const SAVE_PATH := "user://best_times.json"

var track_name: String = ""
var lap_count: int = 0
var current_lap_time: float = 0.0
var last_lap_time: float = -1.0
var best_lap_time: float = -1.0
var sector_times: Array[float] = []
var best_sector_times: Array[float] = []

var _track: TrackData
var _sector_fractions: Array[float] = []
var _last_progress: float = 0.0
var _max_progress: float = 0.0
var _lap_start_time: float = 0.0
var _sim_time: float = 0.0
var _started: bool = false


func _init(track: TrackData) -> void:
	_track = track
	track_name = track.track_name
	_build_sector_fractions()
	best_lap_time = _load_best_lap()
	best_sector_times.resize(_sector_fractions.size())
	best_sector_times.fill(-1.0)
	sector_times.resize(_sector_fractions.size())
	sector_times.fill(-1.0)


func _build_sector_fractions() -> void:
	if _track.timing_lines.is_empty():
		_sector_fractions = [1.0 / 3.0, 2.0 / 3.0]
		return
	var n := float(_track.point_count())
	for line in _track.timing_lines:
		var line_name := str(line.get("name", ""))
		if line_name != "start_finish" and line_name.begins_with("sector"):
			_sector_fractions.append(float(int(line.get("index", 0))) / n)
	_sector_fractions.sort()


## Call every physics tick with the car's global position.
func update(position: Vector3, delta: float) -> void:
	_sim_time += delta
	if not _started:
		_started = true
		_lap_start_time = _sim_time

		# lap completes when progress wraps past the start line and the car has
		# driven past the last sector threshold during this lap
	var previous := _last_progress
	var progress := _progress_of(position)
	for i in range(_sector_fractions.size()):
		var threshold := _sector_fractions[i]
		if previous < threshold and progress >= threshold:
			var split := _sim_time - _lap_start_time
			sector_times[i] = split
			var is_best := best_sector_times[i] < 0.0 or split < best_sector_times[i]
			if is_best:
				best_sector_times[i] = split
			sector_completed.emit(i + 1, split, is_best)

		# lap completes when progress wraps past the start line and the car has
		# driven past the last sector threshold during this lap
	_last_progress = progress
	_max_progress = maxf(_max_progress, progress)

	# lap completes when progress wraps past the start line and the car has
	# driven past the last sector threshold during this lap
	if previous > 0.9 and progress < 0.1 and _max_progress >= _last_sector_threshold():
		lap_count += 1
		var lap_time := _sim_time - _lap_start_time
		last_lap_time = lap_time
		var is_best := best_lap_time < 0.0 or lap_time < best_lap_time
		if is_best:
			best_lap_time = lap_time
			_save_best_lap()
		lap_completed.emit(lap_time, is_best)
		_lap_start_time = _sim_time
		_max_progress = 0.0
	current_lap_time = _sim_time - _lap_start_time


func _last_sector_threshold() -> float:
	if _sector_fractions.is_empty():
		return 0.5
	return _sector_fractions[_sector_fractions.size() - 1]


## Current lap progress 0..1 (used by track-limits measurement in main).
func progress() -> float:
	return _last_progress


## Nearest centerline point fraction (windowed search around last known).
func _progress_of(position: Vector3) -> float:
	var n := _track.point_count()
	var center := int(_last_progress * n)
	var best_index := center
	var best_distance := INF
	var window := 24
	for offset in range(-window, window + 1):
		var index := (center + offset + n) % n
		var distance := _track.points[index].distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return float(best_index) / float(n)


func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.---"
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes * 60)
	return "%02d:%06.3f" % [minutes, rest]


func _load_best_lap() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return -1.0
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary and (data as Dictionary).has(track_name):
		return float((data as Dictionary)[track_name])
	return -1.0


func _save_best_lap() -> void:
	var store := {}
	if FileAccess.file_exists(SAVE_PATH):
		var text := FileAccess.get_file_as_string(SAVE_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			store = parsed
	store[track_name] = best_lap_time
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(store, "  "))
