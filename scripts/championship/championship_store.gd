class_name ChampionshipStore
extends RefCounted
## Offline championship (0.8.0): a season of rounds raced against AI while the
## online league (Phase 3) stays frozen. Pure logic — no autoload references —
## so it is unit-testable in --script mode. The season STATE (schedule, round
## progress, driver names) lives in user://championship.json; every finished
## round is appended to the league ResultsStore (seasons / points / standings
## were built for Phase 3 and are reused as the results backend).
##
## Calendar: track ids cycle over the catalog passed to new_season(). Points:
## standard F1 table via ResultsStore. Driver names are fictional and stable
## per season. A finished season stays visible until a new one is started or
## the old one is abandoned.

const DEFAULT_PATH := "user://championship.json"
const DEFAULT_RESULTS_PATH := "user://league/results.json"
const VERSION := 1
const PLAYER_NAME := "YOU"

## Fictional grid (7 AI names, grid_size is 8 including the player). No
## real-world drivers — master prompt rule.
const AI_NAMES: Array[String] = [
	"K. VOSS",
	"L. MAREK",
	"R. OKONKWO",
	"D. SILVA",
	"A. TANAKA",
	"M. ILES",
	"P. DUBOIS",
]
const DIFFICULTIES: Array[String] = ["rookie", "pro", "legend"]
const ROUND_CHOICES: Array[int] = [4, 6]

const KEY_STATE := "state"
const KEY_VERSION := "version"

var path: String = DEFAULT_PATH
var results_path: String = DEFAULT_RESULTS_PATH

var _results: ResultsStore


func _init(p_path: String = DEFAULT_PATH, p_results_path: String = DEFAULT_RESULTS_PATH) -> void:
	path = p_path
	results_path = p_results_path
	_results = ResultsStore.new()
	_results.path = results_path


## ------------------------------------------------------------- season setup


## Creates a fresh season, replacing any previous one (history of old seasons
## stays in the results backend under its own season key). catalog: Array of
## {id, name, path} entries (Settings.TRACKS shape); the schedule cycles it.
## laps: per-round lap count. Returns false if the catalog is empty.
func new_season(rounds: int, difficulty: String, laps: int, catalog: Array) -> bool:
	var ids: Array[String] = []
	for entry in catalog:
		var id := str(entry.get("id", ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	if ids.is_empty():
		return false
	var count := clampi(rounds, 1, 24)
	var schedule: Array[String] = []
	for i in range(count):
		schedule.append(ids[i % ids.size()])
	if not DIFFICULTIES.has(difficulty):
		difficulty = "pro"
	var state := {
		"schedule": schedule,
		"round": 0,
		"difficulty": difficulty,
		"laps": clampi(laps, 1, 99),
		"names": _grid_names(),
		"season_key": _next_season_key(),
		"done": false,
		"created": Time.get_date_string_from_system(),
	}
	return _save({KEY_VERSION: VERSION, KEY_STATE: state})


## The round to race next: {index (0-based), track_id, laps, difficulty} or
## {} when no active season / the season is complete.
func next_round() -> Dictionary:
	var state := _state()
	if state.is_empty() or bool(state.get("done", false)):
		return {}
	var schedule: Array = state.get("schedule", [])
	var round_index := int(state.get("round", 0))
	if round_index < 0 or round_index >= schedule.size():
		return {}
	return {
		"index": round_index,
		"track_id": str(schedule[round_index]),
		"laps": int(state.get("laps", 5)),
		"difficulty": str(state.get("difficulty", "pro")),
	}


## Records a finished round and advances the season. classification: the
## RaceSession format — [{position, car_index, laps, best_lap, finish_time}].
## Returns {standings, season_done, round_index} or {} on failure.
func record_result(classification: Array) -> Dictionary:
	var state := _state()
	if state.is_empty() or bool(state.get("done", false)):
		return {}
	var schedule: Array = state.get("schedule", [])
	var round_index := int(state.get("round", 0))
	if round_index < 0 or round_index >= schedule.size() or classification.is_empty():
		return {}
	var names: Array = state.get("names", _grid_names())
	var rows: Array = []
	for entry: Dictionary in classification:
		var car_index := int(entry.get("car_index", -1))
		var name := _driver_name(car_index, names)
		(
			rows
			. append(
				{
					"slot": car_index,
					"name": name,
					"position": int(entry.get("position", 0)),
					"laps": int(entry.get("laps", 0)),
					"best_lap": float(entry.get("best_lap", -1.0)),
					"finish_time": float(entry.get("finish_time", -1.0)),
				}
			)
		)
	var race_id := (
		_results
		. save_race(
			str(state.get("season_key", "")),
			{
				"track": str(schedule[round_index]),
				"laps": int(state.get("laps", 5)),
				"date": Time.get_date_string_from_system(),
				"classification": rows,
			}
		)
	)
	if race_id < 0:
		return {}
	var player_row := {}
	for row: Dictionary in rows:
		if str(row.get("name", "")) == PLAYER_NAME:
			player_row = row
			break
	var history: Array = state.get("player_results", [])
	if not history is Array:
		history = []
	(
		history
		. append(
			{
				"track": str(schedule[round_index]),
				"position": int(player_row.get("position", 0)),
				"points": _results.points_for_position(int(player_row.get("position", 0))),
				"best_lap": float(player_row.get("best_lap", -1.0)),
			}
		)
	)
	state["player_results"] = history
	state["round"] = round_index + 1
	if int(state["round"]) >= schedule.size():
		state["done"] = true
	if not _save({KEY_VERSION: VERSION, KEY_STATE: state}):
		return {}
	return {
		"standings": standings(),
		"season_done": bool(state.get("done", false)),
		"round_index": round_index,
	}


## Player history for the schedule panel without touching the results
## backend: [{track, position, points, best_lap}] per completed round.
func player_results() -> Array:
	var state := _state()
	if state.is_empty():
		return []
	var out: Variant = state.get("player_results", [])
	return out if out is Array else []


## ------------------------------------------------------------- accessors


## True when a season exists and still has rounds to race.
func is_active() -> bool:
	return not next_round().is_empty()


## Full stored state (schedule, round, names, done, season_key...). Empty when
## there is no season file or it is corrupt.
func state() -> Dictionary:
	return _state()


## Championship table for the current season key (ResultsStore aggregation):
## [{name, races, wins, podiums, points, best_lap}] sorted by points.
func standings() -> Array:
	var state := _state()
	if state.is_empty():
		return []
	return _results.standings(str(state.get("season_key", "")))


## Drops the active season (start-over). Results history of finished rounds
## keeps living under its season key in the results backend.
func abandon() -> void:
	_save({})


## ------------------------------------------------------------- internals


## Grid names: player first, then the fictional AI list. Stored per season so
## names stay stable across rounds.
func _grid_names() -> Array[String]:
	var out: Array[String] = [PLAYER_NAME]
	out.append_array(AI_NAMES)
	return out


## Stable driver name by grid slot; the roster holds all 8 names with the
## player at index 0, so slot i maps to names[i] directly.
func _driver_name(car_index: int, names: Array) -> String:
	if car_index < 0:
		return "AI%d" % car_index
	if car_index < names.size():
		return str(names[car_index])
	return "AI%d" % car_index


## Season key for the results backend: champ-1, champ-2, ... (increments so
## a new season never mixes into an old table).
func _next_season_key() -> String:
	var seasons: Dictionary = _results._load().get("seasons", {})
	var highest := 0
	for key in seasons:
		var text := str(key)
		if text.begins_with("champ-") and text.substr(6).is_valid_int():
			highest = maxi(highest, int(text.substr(6)))
	return "champ-%d" % (highest + 1)


func _state() -> Dictionary:
	var data := _load()
	var state: Variant = data.get(KEY_STATE, {})
	return state if state is Dictionary else {}


func _load() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("championship_store: corrupt store at %s" % path)
	return {}


## Atomic write: tmp file first, then rename over the target.
func _save(data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("championship_store: cannot open %s for write" % tmp)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)
	)
	if err != OK:
		push_error("championship_store: rename failed (%d)" % err)
		return false
	return true
