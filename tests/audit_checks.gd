class_name AuditChecks
extends RefCounted
## External-audit regression checks (0.9.0 → 0.10.1), extracted from
## run_tests.gd to keep the suite under the gdlint file-size limit.
## Call AuditChecks.run(_check).

const RACE_CONFIG_PATH := "res://assets/data/race_config.json"


static func run(check: Callable) -> void:
	print("[audit fixes]")
	var track := TrackData.load_from("res://tracks/alpha_loop.json")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RACE_CONFIG_PATH))
	var n := track.point_count()

	_windowed_progress_checks(check, track, config, n)
	_geometric_distance_checks(check, track, config)
	_inertia_and_hud_checks(check, config)
	_shadow_budget_checks(check)


## A1: the windowed race progress search must match a full-scan
## reference forward (with lap wrap), backwards, and after a teleport.
static func _windowed_progress_checks(
	check: Callable, track: TrackData, config: Dictionary, n: int
) -> void:
	var session := RaceSession.new(track, config, 2)
	var idx := 3
	var forward_ok := true
	for _step in range(n + 10):
		idx = (idx + 1) % n
		var pos: Vector3 = track.points[idx]
		session._track_car(0, pos, 1.0 / 120.0)
		if absf(session.progress[0] - _full_scan_progress(track, pos)) > 0.005:
			forward_ok = false
	check.call(forward_ok, "windowed progress tracks a forward lap (wrap-safe)")
	var back_ok := true
	for _step in range(30):
		idx = (idx - 1 + n) % n
		var pos: Vector3 = track.points[idx]
		session._track_car(1, pos, 1.0 / 120.0)
		if absf(session.progress[1] - _full_scan_progress(track, pos)) > 0.005:
			back_ok = false
	check.call(back_ok, "windowed progress tracks backwards driving")
	var teleport: Vector3 = track.points[(idx + int(n * 0.5)) % n]
	session._track_car(0, teleport, 1.0 / 120.0)
	var teleport_err := absf(session.progress[0] - _full_scan_progress(track, teleport))
	check.call(teleport_err < 0.005, "teleport falls back to a full scan")


## C1: on-track distance ignores completed laps (pure geometry) — the
## old lap-adjusted delta clamped to 0 m and faked DRS availability.
static func _geometric_distance_checks(
	check: Callable, track: TrackData, config: Dictionary
) -> void:
	var lap_len := track.lap_length()
	var s2 := RaceSession.new(track, config, 2)
	s2.progress[0] = 0.55
	s2.progress[1] = 0.5
	s2.laps_completed[0] = 1
	s2.laps_completed[1] = 0
	var lapped_err := absf(s2._distance_ahead(0, 1) - 0.05 * lap_len)
	check.call(lapped_err < 0.5, "car a lap up: DRS gap reads the real on-track distance")
	s2.progress[0] = 0.4
	s2.progress[1] = 0.6
	s2.laps_completed[0] = 0
	s2.laps_completed[1] = 2
	var backmarker_err := absf(s2._distance_ahead(0, 1) - 0.8 * lap_len)
	check.call(backmarker_err < 0.5, "backmarker ahead: distance wraps geometrically")


## B1: body inertia comes from vehicle.json. A3: standings rows are
## reused across order changes, never freed/recreated.
static func _inertia_and_hud_checks(check: Callable, config: Dictionary) -> void:
	var track := TrackData.load_from("res://tracks/alpha_loop.json")
	var car := VehicleFactory.build(Color(0.2, 0.4, 0.9), "AuditCar")
	# SceneTree scripts get no first frame in _initialize, so _ready never
	# fires on add_child here — run the production setup body directly.
	car._ready()
	var inertia_ok := car.inertia.is_equal_approx(Vector3(1215.0, 1440.0, 300.0))
	check.call(inertia_ok, "body inertia matches vehicle.json pitch/yaw/roll")

	var s2 := RaceSession.new(track, config, 2)
	var hud := RaceHud.new(car, s2, 0)
	hud._update_standings()
	var before := hud._standings_box.get_children().duplicate()
	check.call(before.size() == 2, "standings built one slab per car")
	s2.progress[0] = 0.2
	s2.progress[1] = 0.9
	hud._update_standings()
	var after: Array[Node] = hud._standings_box.get_children()
	var same_rows := true
	for c in before:
		if not after.has(c):
			same_rows = false
	check.call(same_rows, "standings rows are reused across order changes")
	var pos_text: String = (hud._standings_rows[0]["pos"] as Label).text
	check.call(pos_text == "P2", "pos labels follow the new order")
	hud.free()
	car.free()


## Render audit: directional shadow budget per quality preset.
static func _shadow_budget_checks(check: Callable) -> void:
	var settings = load("res://scripts/settings.gd").new()
	settings.quality = "low"
	var low_ok := absf(settings.shadow_max_distance() - 40.0) < 0.01
	check.call(low_ok, "low preset caps shadows at 40 m")
	settings.quality = "medium"
	var medium_ok := absf(settings.shadow_max_distance() - 60.0) < 0.01
	check.call(medium_ok, "medium preset caps shadows at 60 m")
	settings.quality = "high"
	var high_ok := absf(settings.shadow_max_distance() - 100.0) < 0.01
	check.call(high_ok, "high preset keeps 100 m shadows")
	settings.free()


## Full-scan nearest centerline fraction — the correctness reference for
## the windowed race progress search (audit A1).
static func _full_scan_progress(track: TrackData, pos: Vector3) -> float:
	var n := track.point_count()
	var best := 0
	var best_d := INF
	for i in range(n):
		var d: float = track.points[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return float(best) / float(n)
