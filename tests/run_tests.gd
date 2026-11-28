extends SceneTree
## Apex GP test suite (headless). Run:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Groups: project config, track validator, Time Trial logic, vehicle physics
## (no free speed, braking distance, steering symmetry, determinism).
## Exit code 0 = all passed.

const PhysicsDriverScript := preload("res://tests/physics_driver.gd")
const Phase2DriverScript := preload("res://tests/phase2_driver.gd")
const AudioChecksScript := preload("res://tests/audio_checks.gd")
const FeatureChecksScript := preload("res://tests/feature_checks.gd")
const ChampionshipChecksScript := preload("res://tests/championship_checks.gd")
const WeatherChecksScript := preload("res://tests/weather_checks.gd")
const UiRestyleChecksScript := preload("res://tests/ui_restyle_checks.gd")
const AuditChecksScript := preload("res://tests/audit_checks.gd")
const PerfChecksScript := preload("res://tests/perf_checks.gd")

var _checks: int = 0
var _failures: Array[String] = []

var _scenarios: Array[Dictionary] = [
	{"name": "no_free_speed", "duration_ticks": 600},
	{"name": "accel_brake", "duration_ticks": 3600},
	{"name": "steer_left", "duration_ticks": 420},
	{"name": "steer_right", "duration_ticks": 420},
	{"name": "accel_det", "duration_ticks": 840},
	{"name": "accel_det", "duration_ticks": 840},
	{"name": "aero_clean", "duration_ticks": 1680},
	{"name": "aero_wake", "duration_ticks": 1680},
	{"name": "aero_drs", "duration_ticks": 1680},
	{"name": "car_collision", "duration_ticks": 1800},
	{"name": "ai_lap", "duration_ticks": 11400},
]
var _current_scenario: Dictionary = {}
var _results: Dictionary = {}
var _world: Node3D = null
var _driver: Node = null


func _initialize() -> void:
	print("== Apex GP test suite ==")
	_test_config()
	_test_audio()
	_test_features()
	_test_championship()
	_test_weather()
	_test_ui_restyle()
	_test_track_validator()
	_test_vehicle_visuals()
	_test_time_trial_logic()
	_test_racing_line_and_profile()
	_test_race_logic()
	_test_audit_fixes()
	_test_perf_fixes()
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
	_check(main_scene == "res://scenes/menu.tscn", "entry scene is the main menu")
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
		"drs",
		"pause_game",
	]
	for action in required:
		var defined: bool = InputMap.has_action(action)
		_check(defined, "action '%s' is defined" % action)
		if defined:
			var events: Array = InputMap.action_get_events(action)
			_check(not events.is_empty(), "action '%s' has events" % action)

		# explicit mobile rendering method: default Forward+ falls back to
		# software Vulkan (lavapipe, ~15 FPS) on machines without real drivers

		# settings persistence round-trip (0.4.0): the autoload is a runtime
		# node, compile-time identifier is unavailable in a SceneTree script
	var settings_path: Variant = ProjectSettings.get_setting("autoload/Settings", "")
	_check(settings_path == "*res://scripts/settings.gd", "Settings autoload is registered")

	# explicit gl_compatibility method (0.10.2): the Mobile renderer needs
	# Vulkan; weak phones and Vulkan-less desktops end up on software
	# Vulkan (lavapipe, ~15 FPS) or fail entirely
	var renderer: Variant = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	_check(
		renderer == "gl_compatibility",
		"explicit gl_compatibility rendering method (no software fallback)"
	)

	# settings persistence round-trip (0.4.0): the autoload is a runtime
	# node, compile-time identifier is unavailable in a SceneTree script
	var settings_node: Node = root.get_node("Settings")
	var original_quality: String = settings_node.quality
	var original_assists: Dictionary = settings_node.assists.duplicate()
	settings_node.quality = "low"
	settings_node.assists["racing_line"] = true
	settings_node.save_settings()
	settings_node.quality = "high"
	settings_node.assists["racing_line"] = false
	settings_node.load_settings()
	_check(settings_node.quality == "low", "settings round-trip keeps quality")
	_check(bool(settings_node.assists["racing_line"]), "settings round-trip keeps assists")
	settings_node.quality = original_quality
	settings_node.assists = original_assists
	settings_node.save_settings()


# ----------------------------------------------------------- audio tests


func _test_audio() -> void:
	AudioChecksScript.run(_check, root)


func _test_features() -> void:
	FeatureChecksScript.run(_check, root)


func _test_championship() -> void:
	ChampionshipChecksScript.run(_check, root)


func _test_weather() -> void:
	WeatherChecksScript.run(_check, root)


func _test_ui_restyle() -> void:
	UiRestyleChecksScript.run(_check, root)


# -------------------------------------------------------- validator tests


func _test_track_validator() -> void:
	print("[track validator]")
	var alpha := TrackData.load_from("res://tracks/alpha_loop.json")
	if alpha == null:
		_check(false, "alpha_loop.json parses")
		return

		# broken: not closed

		# broken: narrow width

		# broken: figure-8 self-intersection (8 points)

		# broken: not closed

		# broken: narrow width

		# broken: figure-8 self-intersection (8 points)
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


# ------------------------------------------------------ vehicle visuals


func _test_vehicle_visuals() -> void:
	print("[vehicle visuals]")
	var car := VehicleFactory.build(Color(0.2, 0.4, 0.9), "TestCar")
	var body := car.get_node_or_null("Visuals/Body") as Node3D
	_check(body != null, "Sketchfab body attached to car visuals")
	if body == null:
		return

		# calibration: body AABB must match the physics reference points

		# calibration: body AABB must match the physics reference points

		# calibration: body AABB must match the physics reference points
	var mesh_count := 0
	var hidden_tires := 0
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			mesh_count += 1

			# calibration: body AABB must match the physics reference points
		var lname := String(n.name).to_lower()
		if n is Node3D and lname.contains("tire") and not (n as Node3D).visible:
			hidden_tires += 1

			# calibration: body AABB must match the physics reference points
		for c in n.get_children():
			stack.append(c)

			# calibration: body AABB must match the physics reference points

		# calibration: body AABB must match the physics reference points
	_check(mesh_count == 1, "merged body: one draw node for imported meshes (%d)" % mesh_count)
	_check(
		hidden_tires == 0,
		"glb tires excluded from merged body, wheels own visuals (%d)" % hidden_tires
	)
	# calibration: body AABB must match the physics reference points
	var aabb := _body_aabb(body)
	var bottom := aabb.position.y
	var mid_z := aabb.get_center().z
	_check(
		absf(bottom - (-0.47)) < 0.03, "body bottom at collision-box level (bottom %.3f)" % bottom
	)
	_check(absf(mid_z - (-0.155)) < 0.03, "body axle midpoint matches physics (%.3f)" % mid_z)
	_check(aabb.size.x > 1.9, "body covers the track width (%.2f m)" % aabb.size.x)
	car.free()


## AABB of the body INCLUDING its calibration offset (root transform applied).
func _body_aabb(body: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	var stack: Array = [[body, body.transform]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D and n != body:
			xf = xf * (n as Node3D).transform
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var box := xf * mi.mesh.get_aabb()
			if first:
				aabb = box
				first = false
			else:
				aabb = aabb.merge(box)
		for c in n.get_children():
			stack.append([c, xf])
	return aabb


# ------------------------------------------------------ time trial tests


func _test_time_trial_logic() -> void:
	print("[time trial]")
	var save_path := ProjectSettings.globalize_path(TimeTrial.SAVE_PATH)
	if FileAccess.file_exists(TimeTrial.SAVE_PATH):
		DirAccess.remove_absolute(save_path)

		# two full laps, one point per update, 0.1 s per tick -> 4.0 s per lap

		# back-and-forth near the start line must not count a lap

		# persistence: best lap is saved and reloaded

		# two full laps, one point per update, 0.1 s per tick -> 4.0 s per lap

		# back-and-forth near the start line must not count a lap

		# persistence: best lap is saved and reloaded

		# back-and-forth near the start line must not count a lap

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded
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

			# back-and-forth near the start line must not count a lap

			# persistence: best lap is saved and reloaded

		# back-and-forth near the start line must not count a lap

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded
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

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded
	for i in range(5):
		session2.update(track.points[4 - i], 0.1)

		# persistence: best lap is saved and reloaded

		# persistence: best lap is saved and reloaded
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
	var scenario_name: String = _current_scenario["name"]
	if scenario_name == "ai_lap":
		_start_ai_lap()
	elif (
		scenario_name == "aero_clean" or scenario_name == "aero_wake" or scenario_name == "aero_drs"
	):
		_start_aero(scenario_name)
	elif scenario_name == "car_collision":
		_start_car_collision()
	else:
		_start_classic()


func _start_classic() -> void:
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


func _start_ai_lap() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var track := TrackData.load_from("res://tracks/alpha_loop.json")
	TrackBuilder.build(track, _world)
	var line := RacingLine.build(track, 2.0, 0.9, 9)
	var vehicle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	)
	var profile := SpeedProfile.build(line, vehicle, 0.65)
	var car := VehicleFactory.build()
	_world.add_child(car)
	car.global_transform = TrackBuilder.spawn_transform(track)
	var ai := AiDriver.new()
	_world.add_child(ai)
	ai.setup(car, track, line, profile, {"mu_eff": 0.65, "pace": 1.0, "steer_noise": 0.01}, 4242)
	_driver = Phase2DriverScript.new()
	_driver.scenario = "ai_lap"
	_driver.duration_ticks = _current_scenario["duration_ticks"]
	_driver.car = car
	_driver.track = track
	_driver.ai = ai
	ai.reset_requested.connect(func() -> void: _driver.resets += 1)
	_world.add_child(_driver)
	_driver.done.connect(_on_scenario_done)


func _start_aero(scenario_name: String) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_build_ground(_world)
	var car := VehicleFactory.build()
	_world.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0))
	_driver = Phase2DriverScript.new()
	_driver.scenario = scenario_name
	_driver.duration_ticks = _current_scenario["duration_ticks"]
	_driver.car = car
	_world.add_child(_driver)
	_driver.done.connect(_on_scenario_done)


func _start_car_collision() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_build_ground(_world)
	var car := VehicleFactory.build()
	_world.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0))
	var car_b := VehicleFactory.build()
	_world.add_child(car_b)
	# cars overlap by 0.8 m side by side: solver must separate them
	car_b.global_transform = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.7, 0))
	_driver = Phase2DriverScript.new()
	_driver.scenario = "car_collision"
	_driver.duration_ticks = _current_scenario["duration_ticks"]
	_driver.car = car
	_driver.car_b = car_b
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


func _evaluate(driver: Node) -> void:
	var scenario: String = _current_scenario["name"]
	if scenario == "aero_clean" or scenario == "aero_wake" or scenario == "aero_drs":
		_evaluate_aero(driver)
		return
	if scenario == "car_collision":
		_evaluate_car_collision(driver)
		return
	if scenario == "ai_lap":
		_evaluate_ai_lap(driver)
		return
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


func _evaluate_accel_brake(driver: Node) -> void:
	var max_speed := 0.0
	for entry in driver.telemetry:
		max_speed = maxf(max_speed, entry["speed"])

		# braking distance between 300 km/h (83.3 m/s) and 100 km/h (27.8 m/s)

		# braking distance between 300 km/h (83.3 m/s) and 100 km/h (27.8 m/s)
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


# ------------------------------------------------------- phase 2: AI core


func _test_racing_line_and_profile() -> void:
	print("[racing line + speed profile]")
	var track := TrackData.load_from("res://tracks/alpha_loop.json")
	var line := RacingLine.build(track, 2.0, 0.9, 9)
	_check(line.points.size() == track.point_count(), "line has one point per track point")
	var in_bounds := true
	var nan := false
	for i in range(line.points.size()):
		var d: float = line.points[i].distance_to(track.points[i])
		if d > track.widths[i] * 0.5:
			in_bounds = false

			# braking pass monotonicity: speeds never demand more than a_brake
			# between consecutive points

			# difficulty ordering: legend profile >= pro >= rookie corner speeds
		if is_nan(d) or is_nan(line.offsets[i]):
			nan = true

			# braking pass monotonicity: speeds never demand more than a_brake
			# between consecutive points

			# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# braking pass monotonicity: speeds never demand more than a_brake
		# between consecutive points

		# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# braking pass monotonicity: speeds never demand more than a_brake
		# between consecutive points

		# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# difficulty ordering: legend profile >= pro >= rookie corner speeds
	_check(in_bounds, "line stays within the track width")
	_check(not nan, "line has no NaNs")
	var vehicle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	)
	var profile := SpeedProfile.build(line, vehicle, 0.65)
	var ok := true
	var vmin := INF
	var vmax := -INF
	for v in profile.speeds:
		if is_nan(v) or v < 2.0 or v > 90.0:
			ok = false

			# braking pass monotonicity: speeds never demand more than a_brake
			# between consecutive points

			# difficulty ordering: legend profile >= pro >= rookie corner speeds
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)

		# braking pass monotonicity: speeds never demand more than a_brake
		# between consecutive points

		# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# braking pass monotonicity: speeds never demand more than a_brake
		# between consecutive points

		# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# difficulty ordering: legend profile >= pro >= rookie corner speeds
	_check(ok, "profile speeds are finite and sane (2..90 m/s)")
	_check(vmax > 35.0, "profile uses the straights (%.1f m/s max)" % vmax)
	_check(vmin < 12.0, "profile respects the tightest corner (%.1f m/s min)" % vmin)
	# braking pass monotonicity: speeds never demand more than a_brake
	# between consecutive points
	var brake_ok := true
	var n := line.points.size()
	for i in range(n):
		var v0: float = profile.at(i)
		var v1: float = profile.at((i + 1) % n)
		var dist: float = line.lengths[i]
		var a := (v0 * v0 - v1 * v1) / (2.0 * maxf(dist, 0.1)) if v0 > v1 else 0.0
		if a > 18.0:
			brake_ok = false

			# difficulty ordering: legend profile >= pro >= rookie corner speeds

		# difficulty ordering: legend profile >= pro >= rookie corner speeds
	_check(brake_ok, "braking decel within 18 m/s^2 everywhere")
	# difficulty ordering: legend profile >= pro >= rookie corner speeds
	var p_rookie := SpeedProfile.build(line, vehicle, 0.58)
	var p_legend := SpeedProfile.build(line, vehicle, 0.72)
	var legend_faster := true
	for i in range(n):
		if p_legend.at(i) < p_rookie.at(i) - 0.01:
			legend_faster = false
	_check(legend_faster, "legend corner speeds >= rookie corner speeds")


# ------------------------------------------------------ phase 2: race logic


func _test_race_logic() -> void:
	print("[race session]")
	var track := TrackData.load_from("res://tracks/alpha_loop.json")
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/data/race_config.json")
	)
	var session := RaceSession.new(track, config, 2)
	# grid transforms: distinct, behind the start line, inside the road
	var grid := RaceSession.new(track, config, 8).grid_transforms()
	_check(grid.size() == 8, "grid has 8 transforms")
	var distinct := true
	var on_road := true
	var behind := true
	var seen: Array[Vector3] = []
	for t in grid:
		var p: Vector3 = t.origin
		for q in seen:
			if p.distance_to(q) < 2.0:
				distinct = false

				# grid must sit behind the start (progress ~ 1-0.1, not past it)

				# grid must sit behind the start (progress ~ 1-0.1, not past it)

				# grid must sit behind the start (progress ~ 1-0.1, not past it)

				# synthetic race: two cars, the leader one point ahead each step

				# DRS availability with synthetic states: two cars nose-to-tail in a
				# DRS zone at speed -> available; far apart -> not

				# wake: solo car gets none (checked after the far-apart update)
		seen.append(p)
		var nearest := 0
		var nearest_d := INF
		for i in range(track.point_count()):
			var d: float = track.points[i].distance_to(p)
			if d < nearest_d:
				nearest_d = d
				nearest = i

				# grid must sit behind the start (progress ~ 1-0.1, not past it)

				# grid must sit behind the start (progress ~ 1-0.1, not past it)

				# synthetic race: two cars, the leader one point ahead each step

				# DRS availability with synthetic states: two cars nose-to-tail in a
				# DRS zone at speed -> available; far apart -> not

				# wake: solo car gets none (checked after the far-apart update)
		if nearest_d > track.widths[nearest] * 0.5 + 1.0:
			on_road = false
			# grid must sit behind the start (progress ~ 1-0.1, not past it)

			# synthetic race: two cars, the leader one point ahead each step

			# DRS availability with synthetic states: two cars nose-to-tail in a
			# DRS zone at speed -> available; far apart -> not

			# wake: solo car gets none (checked after the far-apart update)
		var prog := float(nearest) / float(track.point_count())
		if not (prog > 0.85 or prog < 0.05):
			behind = false

			# synthetic race: two cars, the leader one point ahead each step

			# DRS availability with synthetic states: two cars nose-to-tail in a
			# DRS zone at speed -> available; far apart -> not

			# wake: solo car gets none (checked after the far-apart update)

		# synthetic race: two cars, the leader one point ahead each step

		# DRS availability with synthetic states: two cars nose-to-tail in a
		# DRS zone at speed -> available; far apart -> not

		# wake: solo car gets none (checked after the far-apart update)

		# DRS availability with synthetic states: two cars nose-to-tail in a
		# DRS zone at speed -> available; far apart -> not

		# wake: solo car gets none (checked after the far-apart update)

		# wake: solo car gets none (checked after the far-apart update)
	_check(distinct, "grid slots are distinct")
	_check(on_road, "grid slots are on the road")
	_check(behind, "grid slots sit behind the start line")

	# synthetic race: two cars, the leader one point ahead each step
	var laps_seen: Array = []
	session.lap_completed.connect(
		func(car_index: int, lap_time: float) -> void: laps_seen.append(car_index)
	)
	config["laps"] = 1
	session.total_laps = 1
	session.start_race()
	var n := track.point_count()
	for step in range(n * 2 + 8):
		var states: Array = []
		for car in range(2):
			var i := (step + car) % n
			(
				states
				. append(
					{
						"pos": track.points[i],
						"forward": track.direction_at(i),
						"speed": 30.0,
					}
				)
			)

			# DRS availability with synthetic states: two cars nose-to-tail in a
			# DRS zone at speed -> available; far apart -> not

			# wake: solo car gets none (checked after the far-apart update)
		session.update(states, 1.0 / 120.0)

		# DRS availability with synthetic states: two cars nose-to-tail in a
		# DRS zone at speed -> available; far apart -> not

		# wake: solo car gets none (checked after the far-apart update)

		# DRS availability with synthetic states: two cars nose-to-tail in a
		# DRS zone at speed -> available; far apart -> not

		# wake: solo car gets none (checked after the far-apart update)

		# wake: solo car gets none (checked after the far-apart update)
	_check(laps_seen.size() == 2, "two lap completions counted (%d)" % laps_seen.size())
	_check(laps_seen[0] == 1, "the car ahead completes the lap first")
	var order := session.positions()
	_check(order[0] == 1, "leader classified ahead")
	var cls: Array = session.classification
	_check(not cls.is_empty(), "classification exists after the race")
	if not cls.is_empty():
		_check(int(cls[0]["position"]) == 1, "winner at P1")
		_check(int(cls[0]["car_index"]) == 1, "winner is the leader car")

		# DRS availability with synthetic states: two cars nose-to-tail in a
		# DRS zone at speed -> available; far apart -> not

		# wake: solo car gets none (checked after the far-apart update)

		# wake: solo car gets none (checked after the far-apart update)
	var drs_session := RaceSession.new(track, config, 2)
	drs_session.start_race()
	var zone: Dictionary = track.drs_zones[0]
	var zone_i := int(zone.get("start_index", 0)) + 2
	var states: Array = [
		{
			"pos": track.points[zone_i],
			"forward": track.direction_at(zone_i),
			"speed": 70.0,
		},
	]
	var ahead_i := (zone_i + 1) % track.point_count()
	(
		states
		. append(
			{
				"pos": track.points[ahead_i],
				"forward": track.direction_at(ahead_i),
				"speed": 70.0,
			}
		)
	)
	drs_session.update(states, 1.0 / 120.0)
	_check(drs_session.drs_available(0), "DRS available close behind in a zone")
	_check(drs_session.wake_df(0) > 0.0, "dirty air factor positive behind a car")
	_check(drs_session.wake_drag(0) > 0.0, "slipstream factor positive behind a car")
	var far_states: Array = [
		{
			"pos": track.points[zone_i],
			"forward": track.direction_at(zone_i),
			"speed": 70.0,
		},
		{
			"pos": track.points[(zone_i + 20) % track.point_count()],
			"forward": track.direction_at((zone_i + 20) % track.point_count()),
			"speed": 70.0,
		},
	]
	drs_session.update(far_states, 1.0 / 120.0)
	_check(not drs_session.drs_available(0), "DRS not available with a big gap")

	# wake: solo car gets none (checked after the far-apart update)
	var solo := RaceSession.new(track, config, 1)
	solo.start_race()
	solo.update(states.slice(0, 1), 1.0 / 120.0)
	_check(solo.wake_df(0) == 0.0 and solo.wake_drag(0) == 0.0, "solo car has clean air")


# -------------------------------------------------- phase 2 scenario checks


func _evaluate_aero(driver: Node) -> void:
	var d: Phase2Driver = driver as Phase2Driver
	var scenario: String = _current_scenario["name"]
	_results[scenario] = d.telemetry[d.telemetry.size() - 1]
	if scenario == "aero_clean":
		return
	if scenario == "aero_wake":
		var clean: float = _results.get("aero_clean", 0.0)
		_check(
			d.telemetry[d.telemetry.size() - 1] > clean + 0.5,
			(
				"slipstream raises top speed (%.1f vs %.1f m/s)"
				% [d.telemetry[d.telemetry.size() - 1], clean]
			)
		)
	elif scenario == "aero_drs":
		var clean: float = _results.get("aero_clean", 0.0)
		# 0.7.0 rolling resistance shifted both scenarios down, so the absolute
		# straight-end delta shrank; require a strictly positive DRS gain
		_check(
			d.telemetry[d.telemetry.size() - 1] > clean + 0.1,
			"DRS raises top speed (%.1f vs %.1f m/s)" % [d.telemetry[d.telemetry.size() - 1], clean]
		)


func _evaluate_car_collision(driver: Node) -> void:
	var d: Phase2Driver = driver as Phase2Driver
	var min_y := INF
	for entry in d.telemetry:
		if entry is Array:
			min_y = minf(min_y, minf(entry[0], entry[1]))

			# boxes are 1.4 m wide: >1.2 m apart means no deep interpenetration lock

		# boxes are 1.4 m wide: >1.2 m apart means no deep interpenetration lock
	_check(min_y > 0.4, "colliding cars stay on the ground (y >= %.2f)" % min_y)
	var car: Car = d.car
	var car_b: Car = d.car_b
	# boxes are 1.4 m wide: >1.2 m apart means no deep interpenetration lock
	_check(
		absf(car.global_transform.origin.x - car_b.global_transform.origin.x) > 1.2,
		(
			"overlapping cars separate (%.2f m apart)"
			% absf(car.global_transform.origin.x - car_b.global_transform.origin.x)
		)
	)
	var upright := car.global_transform.basis.y.dot(Vector3.UP) > 0.7
	var upright_b := car_b.global_transform.basis.y.dot(Vector3.UP) > 0.7
	_check(upright and upright_b, "both cars stay upright after the collision")


func _evaluate_ai_lap(driver: Node) -> void:
	var d: Phase2Driver = driver as Phase2Driver
	_check(d.laps >= 1, "AI completes a lap in 95 s (%d)" % d.laps)
	_check(d.resets == 0, "AI needs no recovery resets (%d)" % d.resets)
	_check(
		d.max_off_center < 7.0 + 2.0,
		"AI stays within road + kerb (max %.1f m off center)" % d.max_off_center
	)


func _test_audit_fixes() -> void:
	AuditChecksScript.run(_check)


func _test_perf_fixes() -> void:
	PerfChecksScript.run(_check)
