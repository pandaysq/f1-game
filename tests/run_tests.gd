extends SceneTree
## Apex GP test suite (headless). Run:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Groups: project config, track validator, Time Trial logic, vehicle physics
## (no free speed, braking distance, steering symmetry, determinism).
## Exit code 0 = all passed.

const PhysicsDriverScript := preload("res://tests/physics_driver.gd")

var _checks: int = 0
var _failures: Array[String] = []

var _scenarios: Array[Dictionary] = [
	{"name": "no_free_speed", "duration_ticks": 600},
	{"name": "accel_brake", "duration_ticks": 3600},
	{"name": "steer_left", "duration_ticks": 420},
	{"name": "steer_right", "duration_ticks": 420},
	{"name": "accel_det", "duration_ticks": 840},
	{"name": "accel_det", "duration_ticks": 840},
]
var _current_scenario: Dictionary = {}
var _results: Dictionary = {}
var _world: Node3D = null
var _driver: PhysicsTestDriver = null


func _initialize() -> void:
	print("== Apex GP test suite ==")
	_test_config()
	_test_track_validator()
	_test_time_trial_logic()
	if not _failures.is_empty():
		_finish()
		return
	_start_next_scenario()


# ----------------------------------------------------------- config tests


func _test_config() -> void:
	print("[config]")
	var ticks: Variant = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)
	_check(ticks == 120, "physics tick rate is 120 Hz")
	var main_scene: Variant = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene == "res://scenes/main.tscn", "main scene is configured")
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()
	)
	_check(features.has("4.5"), "project targets Godot 4.5")
	_check(features.has("Mobile"), "mobile renderer is enabled (Android/iOS target)")
	var required := [
		"throttle",
		"brake",
		"steer_left",
		"steer_right",
		"nitro",
		"shift_up",
		"shift_down",
		"reset_car",
		"toggle_camera",
		"toggle_debug",
	]
	for action in required:
		var defined: bool = InputMap.has_action(action)
		_check(defined, "action '%s' is defined" % action)
		if defined:
			var events: Array = InputMap.action_get_events(action)
			_check(not events.is_empty(), "action '%s' has events" % action)
	var settings_path: Variant = ProjectSettings.get_setting("autoload/Settings", "")
	_check(settings_path == "*res://scripts/settings.gd", "Settings autoload is registered")


# -------------------------------------------------------- validator tests


func _test_track_validator() -> void:
	print("[track validator]")
	var alpha := TrackData.load_from("res://tracks/alpha_loop.json")
	if alpha == null:
		_check(false, "alpha_loop.json parses")
		return
	_check(true, "alpha_loop.json parses")
	var problems := TrackValidator.validate(alpha)
	_check(problems.is_empty(), "alpha_loop.json is valid (%s)" % str(problems))

	# broken: not closed
	var broken := _make_ring()
	broken.closed = false
	var p1 := TrackValidator.validate(broken)
	_check(not p1.is_empty(), "unclosed track is rejected")

	# broken: narrow width
	var narrow := _make_ring()
	narrow.widths[3] = 2.0
	var p2 := TrackValidator.validate(narrow)
	_check(not p2.is_empty(), "narrow track is rejected")

	# broken: figure-8 self-intersection (8 points)
	var cross := TrackData.new()
	cross.closed = true
	cross.track_name = "BrokenCross"
	var pts := [
		Vector3(0, 0, 0),
		Vector3(2, 0, 2),
		Vector3(4, 0, 4),
		Vector3(10, 0, 10),
		Vector3(10, 0, 0),
		Vector3(7, 0, 3),
		Vector3(4, 0, 6),
		Vector3(0, 0, 10),
	]
	for point in pts:
		cross.points.append(point)
		cross.widths.append(14.0)
		cross.banking.append(0.0)
	var p3 := TrackValidator.validate(cross)
	_check(not p3.is_empty(), "self-intersecting track is rejected")


func _make_ring() -> TrackData:
	var track := TrackData.new()
	track.closed = true
	track.track_name = "TestRing"
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		track.points.append(Vector3(cos(angle) * 100.0, 0.0, sin(angle) * 100.0))
		track.widths.append(14.0)
		track.banking.append(0.0)
	track.timing_lines = [
		{"name": "start_finish", "index": 0},
		{"name": "sector_1", "index": 13},
		{"name": "sector_2", "index": 26},
	]
	return track


# ------------------------------------------------------ time trial tests


func _test_time_trial_logic() -> void:
	print("[time trial]")
	var save_path := ProjectSettings.globalize_path(TimeTrial.SAVE_PATH)
	if FileAccess.file_exists(TimeTrial.SAVE_PATH):
		DirAccess.remove_absolute(save_path)

	var track := _make_ring()
	var session := TimeTrial.new(track)
	var laps_seen := [0]
	var sectors_seen := [0]
	session.lap_completed.connect(func(_lap_time: float, _is_best: bool) -> void: laps_seen[0] += 1)
	session.sector_completed.connect(
		func(_sector: int, _time_s: float, _is_best: bool) -> void: sectors_seen[0] += 1
	)
	# two full laps, one point per update, 0.1 s per tick -> 4.0 s per lap
	for lap in range(2):
		for i in range(40):
			session.update(track.points[i], 0.1)
	session.update(track.points[0], 0.1)
	_check(laps_seen[0] == 2, "two laps counted (%d)" % laps_seen[0])
	_check(sectors_seen[0] == 4, "four sector crossings (%d)" % sectors_seen[0])
	_check(
		absf(session.best_lap_time - 4.0) < 0.0001,
		"best lap is 4.0 s (%.3f)" % session.best_lap_time
	)

	# back-and-forth near the start line must not count a lap
	var session2 := TimeTrial.new(track)
	for i in range(6):
		session2.update(track.points[i], 0.1)
	for i in range(5):
		session2.update(track.points[4 - i], 0.1)
	session2.update(track.points[0], 0.1)
	_check(session2.lap_count == 0, "back-and-forth does not count a lap")

	# persistence: best lap is saved and reloaded
	var session3 := TimeTrial.new(track)
	_check(
		absf(session3.best_lap_time - 4.0) < 0.0001,
		"best lap persists across sessions (%.3f)" % session3.best_lap_time
	)
	DirAccess.remove_absolute(save_path)


# --------------------------------------------------------- physics scenarios


func _start_next_scenario() -> void:
	if _scenarios.is_empty():
		_finish()
		return
	_current_scenario = _scenarios.pop_front()
	_world = Node3D.new()
	root.add_child(_world)
	_build_ground(_world)
	var car: Car = VehicleFactory.build()
	_world.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0))
	_driver = PhysicsDriverScript.new()
	_driver.car = car
	_driver.scenario = _current_scenario["name"]
	_driver.duration_ticks = _current_scenario["duration_ticks"]
	_world.add_child(_driver)
	_driver.done.connect(_on_scenario_done)


func _build_ground(world: Node3D) -> void:
	var body := StaticBody3D.new()
	body.set_meta("grip", 1.0)
	body.set_meta("surface", "asphalt")
	var shape := BoxShape3D.new()
	shape.size = Vector3(5000, 2, 5000)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, -1, 0)
	body.add_child(collision)
	world.add_child(body)


func _on_scenario_done() -> void:
	_evaluate(_driver)
	_world.queue_free()
	_world = null
	_driver = null
	_start_next_scenario()


func _evaluate(driver: PhysicsTestDriver) -> void:
	var scenario: String = _current_scenario["name"]
	if scenario == "no_free_speed":
		var max_speed := 0.0
		for i in range(driver.settle_ticks, driver.telemetry.size()):
			max_speed = maxf(max_speed, driver.telemetry[i]["speed"])
		_check(max_speed < 0.5, "no free speed gain (max %.4f m/s)" % max_speed)
	elif scenario == "accel_brake":
		_evaluate_accel_brake(driver)
	elif scenario == "steer_left" or scenario == "steer_right":
		var final_pos: Vector3 = driver.telemetry[driver.telemetry.size() - 1]["pos"]
		_results[scenario] = (final_pos - Vector3(0, 0.7, 0)).length()
		_try_symmetry_check()
	elif scenario == "accel_det":
		var final_pos: Vector3 = driver.telemetry[driver.telemetry.size() - 1]["pos"]
		var final_vel: Vector3 = driver.telemetry[driver.telemetry.size() - 1]["vel"]
		var key := "det_%d" % _results.size()
		_results[key] = {"pos": final_pos, "vel": final_vel}
		var keys := _results.keys().filter(func(k: String) -> bool: return k.begins_with("det_"))
		if keys.size() == 2:
			var a: Dictionary = _results[keys[0]]
			var b: Dictionary = _results[keys[1]]
			_check(
				a["pos"] == b["pos"] and a["vel"] == b["vel"],
				"determinism: identical inputs give identical states"
			)


func _evaluate_accel_brake(driver: PhysicsTestDriver) -> void:
	var max_speed := 0.0
	for entry in driver.telemetry:
		max_speed = maxf(max_speed, entry["speed"])
	_check(max_speed > 60.0 and max_speed < 95.0, "top speed plausible (%.1f m/s)" % max_speed)

	# braking distance between 300 km/h (83.3 m/s) and 100 km/h (27.8 m/s)
	var brake_start_tick := 60 + 22 * 120
	var pos_high := Vector3.ZERO
	var pos_low := Vector3.ZERO
	var found_high := false
	var found_low := false
	for i in range(brake_start_tick, driver.telemetry.size()):
		var speed: float = driver.telemetry[i]["speed"]
		if not found_high and speed <= 83.3:
			pos_high = driver.telemetry[i]["pos"]
			found_high = true
		if found_high and speed <= 27.8:
			pos_low = driver.telemetry[i]["pos"]
			found_low = true
			break
	if found_low:
		var distance := Vector2(pos_low.x, pos_low.z).distance_to(Vector2(pos_high.x, pos_high.z))
		_check(
			distance > 60.0 and distance < 260.0,
			"braking distance 300->100 km/h plausible (%.0f m)" % distance
		)
	else:
		_check(false, "braking phase did not reach 100 km/h")
	var final_speed: float = driver.telemetry[driver.telemetry.size() - 1]["speed"]
	_check(final_speed < 1.0, "car stops after braking (%.2f m/s)" % final_speed)


func _try_symmetry_check() -> void:
	if not _results.has("steer_left") or not _results.has("steer_right"):
		return
	var left: float = _results["steer_left"]
	var right: float = _results["steer_right"]
	var diff := absf(left - right) / maxf(left, right)
	_check(
		diff < 0.02,
		"steering symmetry left/right (%.1f m vs %.1f m, diff %.3f%%)" % [left, right, diff * 100.0]
	)


# ------------------------------------------------------------------ summary


func _check(condition: bool, test_name: String) -> void:
	_checks += 1
	if condition:
		print("  OK   %s" % test_name)
	else:
		_failures.append(test_name)
		print("  FAIL %s" % test_name)


func _finish() -> void:
	if _failures.is_empty():
		print("ALL TESTS PASSED (%d checks)" % _checks)
		quit(0)
	else:
		printerr("%d of %d checks failed:" % [_failures.size(), _checks])
		for failure in _failures:
			printerr("  - %s" % failure)
		quit(1)
