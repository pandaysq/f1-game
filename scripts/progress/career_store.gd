class_name CareerStore
extends RefCounted
## Local career-lite storage (0.6.0): every finished race is appended to
## user://career.json (last 30 kept). Stats drive the STATS panel in the
## menu. No accounts, no sync — device-local progress only (online parts
## stay frozen until Phase 3).

const SAVE_PATH := "user://career.json"
const VERSION := 1
const MAX_RACES := 30

const KEY_RACES := "races"


## Records a finished race. best_lap < 0 means "no lap timed".
static func record_race(
	track_id: String, mode: String, position: int, car_count: int, best_lap: float, laps: int
) -> void:
	var store := load_data()
	var races: Array = store.get(KEY_RACES, [])
	(
		races
		. append(
			{
				"track": track_id,
				"mode": mode,
				"position": position,
				"car_count": car_count,
				"best_lap": snappedf(best_lap, 0.001),
				"laps": laps,
				"date": Time.get_date_string_from_system(),
			}
		)
	)
	while races.size() > MAX_RACES:
		races.pop_front()
	store[KEY_RACES] = races
	store["version"] = VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[Career] cannot save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(store))


static func load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {KEY_RACES: []}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and (parsed as Dictionary).get(KEY_RACES) is Array:
		return parsed
	return {KEY_RACES: []}  # corrupt file: start over


## Aggregates: races/wins/podiums counts + best lap per track id.
static func stats() -> Dictionary:
	var races: Array = load_data().get(KEY_RACES, [])
	var wins := 0
	var podiums := 0
	var best_by_track := {}
	for r in races:
		var position := int(r.get("position", 99))
		if position == 1:
			wins += 1
		if position <= 3:
			podiums += 1
		var track := str(r.get("track", ""))
		var lap := float(r.get("best_lap", -1.0))
		if lap > 0.0:
			if not best_by_track.has(track) or lap < float(best_by_track[track]):
				best_by_track[track] = lap
	return {
		"races": races.size(),
		"wins": wins,
		"podiums": podiums,
		"best_by_track": best_by_track,
	}
