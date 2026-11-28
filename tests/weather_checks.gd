extends RefCounted
## Weather 0.10.0 checks: WeatherState kinds / wetness / calendar determinism,
## TyreCompound grip & wear ordering (dry + slick must stay the untouched
## 0.9.0 physics), the championship weather schedule, and the RaceSession
## interval / laps-behind math behind the new tower gap column.
## Call WeatherChecks.run(check, root).

const STATE_PATH := "user://test_weather_state.json"
const RESULTS_PATH := "user://test_weather_results.json"
const TRACK_PATH := "res://tracks/alpha_loop.json"

const CATALOG: Array = [
	{"id": "endurance_run", "name": "ENDURANCE RUN", "path": "res://tracks/endurance_run.json"},
	{"id": "alpha_loop", "name": "ALPHA LOOP", "path": "res://tracks/alpha_loop.json"},
]


static func run(check: Callable, _root: Node) -> void:
	print("[weather]")
	_test_weather_state(check)
	_test_compound(check)
	_test_intervals(check)
	_test_championship_weather(check)
	_cleanup()


# ------------------------------------------------------------------ weather


static func _test_weather_state(check: Callable) -> void:
	check.call(WeatherState.is_valid("dry"), "dry is a valid kind")
	check.call(
		WeatherState.is_valid("light") and WeatherState.is_valid("heavy"), "rain kinds valid"
	)
	check.call(not WeatherState.is_valid("storm"), "unknown kind rejected")
	check.call(WeatherState.sanitize("heavy") == "heavy", "sanitize keeps valid kinds")
	check.call(WeatherState.sanitize("monsoon") == "dry", "sanitize falls back to dry")
	check.call(is_equal_approx(WeatherState.wetness("dry"), 0.0), "dry track is dry")
	check.call(is_equal_approx(WeatherState.wetness("light"), 0.45), "light rain wets to 0.45")
	check.call(is_equal_approx(WeatherState.wetness("heavy"), 0.85), "heavy rain wets to 0.85")
	check.call(WeatherState.wetness("bogus") == 0.0, "unknown kind has zero wetness")
	check.call(WeatherState.label("light") == "LIGHT RAIN", "broadcast label (light)")
	check.call(WeatherState.label("nope") == "DRY", "broadcast label fallback")
	check.call(WeatherState.icon("dry") == "sun", "dry icon is the sun")
	check.call(WeatherState.icon("light") == "drizzle", "light icon is the drizzle")
	check.call(WeatherState.icon("heavy") == "rain", "heavy icon is the rain")
	var a := WeatherState.season_calendar("champ-3", 4)
	var b := WeatherState.season_calendar("champ-3", 4)
	check.call(a == b, "calendar is deterministic per season key")
	check.call(a.size() == 4, "calendar covers every round")
	for kind in a:
		check.call(WeatherState.is_valid(kind), "calendar entry is a valid kind (%s)" % kind)
	check.call(
		WeatherState.season_calendar("champ-9", 0).size() == 1, "calendar keeps at least one round"
	)


# ---------------------------------------------------------------- compounds


static func _test_compound(check: Callable) -> void:
	check.call(TyreCompound.is_valid("slick"), "slick is a compound")
	check.call(
		TyreCompound.is_valid("inter") and TyreCompound.is_valid("wet"), "rain compounds valid"
	)
	check.call(TyreCompound.sanitize("slk") == "slick", "compound sanitize falls back")
	check.call(
		is_equal_approx(TyreCompound.grip("slick", 0.0), 1.0),
		"dry + slick is exactly the old physics (1.0)"
	)
	check.call(
		TyreCompound.grip("slick", 1.0) < TyreCompound.grip("inter", 1.0),
		"inters beat slicks in heavy rain"
	)
	check.call(
		TyreCompound.grip("inter", 1.0) < TyreCompound.grip("wet", 1.0),
		"wets beat inters in heavy rain"
	)
	check.call(
		TyreCompound.grip("slick", 1.0) < TyreCompound.grip("slick", 0.0),
		"slicks lose grip in rain"
	)
	var damp := TyreCompound.grip("inter", 0.45)
	check.call(damp > TyreCompound.grip("slick", 0.45), "inters beat slicks on a damp track")
	check.call(damp > TyreCompound.grip("wet", 0.45), "inters beat wets on a damp track")
	check.call(TyreCompound.best_for_wetness(0.0) == "slick", "AI picks slicks when dry")
	check.call(TyreCompound.best_for_wetness(0.45) == "inter", "AI picks inters when damp")
	check.call(TyreCompound.best_for_wetness(0.85) == "wet", "AI picks wets in heavy rain")
	check.call(TyreCompound.wear_mult("slick", 0.0) == 1.0, "slick wear untouched on dry")
	check.call(TyreCompound.wear_mult("wet", 0.0) > 1.5, "wets overheat on a dry track")
	check.call(TyreCompound.wear_mult("slick", 1.0) == 1.0, "slicks wear normally in rain")
	var tuned := {"compounds": {"wet": {"grip_wet": 1.05}}}
	check.call(
		is_equal_approx(TyreCompound.grip("wet", 1.0, tuned), 1.05),
		"vehicle.json overrides compound ratings"
	)
	check.call(TyreCompound.letter("inter") == "I", "HUD chip letter (I)")
	check.call(TyreCompound.label("wet") == "WET", "setup label (WET)")
	check.call(TyreCompound.color("slick") == TyreCompound.COLORS["slick"], "chip color map works")


# ---------------------------------------------------------------- intervals


static func _test_intervals(check: Callable) -> void:
	var text := FileAccess.get_file_as_string(TRACK_PATH)
	var track := TrackData.parse(text, TRACK_PATH)
	check.call(track != null, "alpha_loop parses for the session fixture")
	if track == null:
		return
	var session := RaceSession.new(track, {"laps": 3}, 4)
	session.start_race()
	var laps := [2, 2, 2, 1]
	var prog := [0.90, 0.60, 0.75, 0.50]
	var spd := [70.0, 60.0, 60.0, 55.0]
	for i in range(4):
		session.laps_completed[i] = laps[i]
		session.progress[i] = prog[i]
		session.speeds[i] = spd[i]
	check.call(_same_order(session, [0, 2, 1, 3]), "race order laps-first then progress")
	check.call(is_zero_approx(session.interval_ahead_s(0)), "the race leader has no interval")
	var lap_len := track.lap_length()
	var want := (0.90 - 0.75) * lap_len / 60.0
	check.call(
		is_equal_approx(session.interval_ahead_s(1), want),
		"interval = distance over follower speed"
	)
	var want2 := (0.75 - 0.60) * lap_len / 60.0
	check.call(is_equal_approx(session.interval_ahead_s(2), want2), "interval walks the race order")
	check.call(session.laps_behind(3) == 1, "car on 1 lap trails the leader by 1 lap")
	check.call(session.laps_behind(0) == 0, "the leader is on the lead lap")
	var duo := RaceSession.new(track, {"laps": 3}, 2)
	duo.start_race()
	var duo_laps := [2, 1]
	var duo_prog := [0.10, 0.80]
	for i in range(2):
		duo.laps_completed[i] = duo_laps[i]
		duo.progress[i] = duo_prog[i]
		duo.speeds[i] = 60.0
	check.call(
		duo.laps_behind(1) == 0,
		"crossing-count flicker: 0.3 lap of distance is NOT a full lap down"
	)
	check.call(
		is_equal_approx(duo.interval_ahead_s(1), 0.30 * track.lap_length() / 60.0),
		"interval rides the continuous distance across a line crossing"
	)
	session.finished[0] = true
	session.finish_time[0] = 100.0
	session.finished[2] = true
	session.finish_time[2] = 102.5
	check.call(
		is_equal_approx(session.interval_ahead_s(1), 2.5),
		"finished cars gap by the exact finish-time delta"
	)


# --------------------------------------------------------- championship wx


## Element-wise race-order comparison (avoids typed-array literal casts).
static func _same_order(session: RaceSession, want: Array) -> bool:
	var order: Array[int] = session.positions()
	if order.size() != want.size():
		return false
	for i in range(want.size()):
		if order[i] != int(want[i]):
			return false
	return true


static func _test_championship_weather(check: Callable) -> void:
	var store := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	store.abandon()
	check.call(store.new_season(6, "pro", 5, CATALOG), "season created for weather checks")
	var schedule: Array = store.state().get("weather", [])
	check.call(schedule.size() == 6, "season stores a weather kind per round")
	var round_info := store.next_round()
	check.call(
		WeatherState.is_valid(str(round_info.get("weather", ""))),
		"next_round carries a valid weather kind"
	)
	store.abandon()
	store.new_season(6, "pro", 5, CATALOG)
	var again: Array = store.state().get("weather", [])
	check.call(schedule == again, "recreated season shows the same forecast")
	store.abandon()
	check.call(store.next_round().is_empty(), "abandon clears the season")


static func _cleanup() -> void:
	for path in [STATE_PATH, RESULTS_PATH, STATE_PATH + ".tmp", RESULTS_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
