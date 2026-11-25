class_name GhostRecorder
extends RefCounted
## Best-lap recorder for Time Trial (0.6.0): samples the player transform at
## a fixed rate during a lap; the samples of a personal-best lap are stored
## to user://ghosts.json keyed by track name, and replayed by GhostCar.
## JSON is intentionally small: 10 Hz decimation, ~900 samples per lap.

const SAMPLE_PERIOD := 0.1
const SAVE_PATH := "user://ghosts.json"
const VERSION := 1

var _samples: Array = []  # [[t, x, y, z, yaw], ...] time-ordered
var _acc := 0.0


func start_lap() -> void:
	_samples.clear()
	_acc = 0.0


## Feed every physics tick. t = current lap time, yaw = facing angle (rad).
func record(t: float, pos: Vector3, yaw: float, delta: float) -> void:
	_acc += delta
	if _acc < SAMPLE_PERIOD:
		return
	_acc = fmod(_acc, SAMPLE_PERIOD)
	_samples.append(
		[
			snappedf(t, 0.001),
			snappedf(pos.x, 0.01),
			snappedf(pos.y, 0.01),
			snappedf(pos.z, 0.01),
			snappedf(yaw, 0.001)
		]
	)


## Finishes the lap: returns the samples (a copy) and arms the next lap.
func finish_lap() -> Array:
	var out := _samples.duplicate(true)
	_samples.clear()
	_acc = 0.0
	return out


## Persists a personal-best recording for this track. Returns true on success.
static func save_best(track_name: String, lap_time: float, samples: Array) -> bool:
	if samples.size() < 2:
		return false
	var store := _load_store()
	store[track_name] = {"version": VERSION, "lap": snappedf(lap_time, 0.001), "samples": samples}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(store))
	return true


## Returns the stored best-lap samples for this track ([] when none/corrupt).
static func load_best(track_name: String) -> Array:
	var store := _load_store()
	var entry: Variant = store.get(track_name, {})
	if entry is Dictionary:
		var samples: Variant = (entry as Dictionary).get("samples", [])
		if samples is Array and (samples as Array).size() >= 2:
			return samples
	return []


static func _load_store() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}  # corrupt file: start over
