class_name ResultsStore
extends RefCounted
## League results storage (Phase 3). A storage INTERFACE first: the default
## backend is a single JSON document under user:// (atomic tmp+rename write).
## It covers races, points and standings for friendly leagues without adding
## a native SQLite dependency to the project (see docs/DECISIONS.md D-015).
## If the owner later wants real SQLite, swap the backend behind this API.

const DEFAULT_PATH := "user://league/results.json"
const DEFAULT_POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]

var path: String = DEFAULT_PATH
var points_system: Array = DEFAULT_POINTS


## record: {track, laps, date, seed, classification: [{slot, name, position,
## laps, best_lap, finish_time}]}. Returns the race id, or -1 on failure.
func save_race(season: String, record: Dictionary) -> int:
	var data := _load()
	if data.is_empty():
		return -1
	if not data.has("seasons"):
		data["seasons"] = {}
	if not data["seasons"].has(season):
		data["seasons"][season] = {"points_system": points_system, "races": []}
	var season_data: Dictionary = data["seasons"][season]
	if not season_data.has("races"):
		season_data["races"] = []
	var races: Array = season_data["races"]
	var race_id := races.size() + 1
	var entry := {
		"id": race_id,
		"track": str(record.get("track", "unknown")),
		"laps": int(record.get("laps", 0)),
		"date": str(record.get("date", "")),
		"seed": int(record.get("seed", 0)),
		"classification": record.get("classification", []),
	}
	for item: Dictionary in entry["classification"]:
		item["points"] = points_for_position(int(item.get("position", 0)))
	races.append(entry)
	if not _save(data):
		return -1
	return race_id


func points_for_position(position: int) -> int:
	if position < 1 or position > points_system.size():
		return 0
	return int(points_system[position - 1])


## Aggregated season table, sorted by points desc:
## [{name, races, wins, podiums, points, best_lap}]
func standings(season: String) -> Array:
	var data := _load()
	var out_map: Dictionary = {}
	var season_data: Dictionary = data.get("seasons", {}).get(season, {})
	for race: Dictionary in season_data.get("races", []):
		for entry: Dictionary in race.get("classification", []):
			var name := str(entry.get("name", "unknown"))
			if not out_map.has(name):
				out_map[name] = {
					"name": name,
					"races": 0,
					"wins": 0,
					"podiums": 0,
					"points": 0,
					"best_lap": INF,
				}
			var row: Dictionary = out_map[name]
			row["races"] += 1
			var position := int(entry.get("position", 0))
			if position == 1:
				row["wins"] += 1
			if position > 0 and position <= 3:
				row["podiums"] += 1
			row["points"] += int(entry.get("points", 0))
			var best := float(entry.get("best_lap", -1.0))
			if best > 0.0 and best < float(row["best_lap"]):
				row["best_lap"] = best
	var out: Array = []
	for name in out_map:
		var row: Dictionary = out_map[name]
		if float(row["best_lap"]) == INF:
			row["best_lap"] = -1.0
		out.append(row)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["points"]) != int(b["points"]):
				return int(a["points"]) > int(b["points"])
			return int(a["wins"]) > int(b["wins"])
	)
	return out


func _load() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"seasons": {}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("results_store: corrupt store at %s" % path)
	return {"seasons": {}}


## Atomic write: tmp file first, then rename over the target.
func _save(data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("results_store: cannot open %s for write" % tmp)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)
	)
	if err != OK:
		push_error("results_store: rename failed (%d)" % err)
		return false
	return true
