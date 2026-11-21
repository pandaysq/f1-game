extends Node3D
## Phase 2 main scene: builds Alpha Loop, spawns the player car + 7 AI
## cars, runs the offline race session (grid start, countdown, positions,
## DRS rules, aero wake) and wires camera / HUD / touch controls.
## Time Trial (phase 1) stays available: APEX_MODE=tt.

const TICK_DT := 1.0 / 120.0
const TRACK_PATH := "res://tracks/alpha_loop.json"
const RACE_CONFIG_PATH := "res://assets/data/race_config.json"
const ENVIRONMENT_MODEL_PATH := "res://assets/models/environment/endurance_run.glb"
## Backdrop placement: the endurance diorama (1104 x 744 m, local AABB at
## x 159..1263, z 426..1170) must stay clear of the drivable area
## (alpha_loop: x -120..224, z -131..183). Shift seats it ~140 m beyond the
## +Z edge; visual-only, no collision, cars never reach it.
const SCENERY_OFFSET := Vector3(0.0, -0.9, -100.0)

const AI_COLORS := [
	Color(0.88, 0.09, 0.09),
	Color(0.12, 0.45, 0.95),
	Color(0.95, 0.75, 0.1),
	Color(0.1, 0.75, 0.35),
	Color(0.6, 0.2, 0.8),
	Color(0.95, 0.45, 0.1),
	Color(0.5, 0.8, 0.9),
	Color(0.75, 0.75, 0.78),
]

var track: TrackData
var ai_line: RacingLine
var cars: Array[Car] = []
var drivers: Array[AiDriver] = []
var session: RaceSession
var tt_session: TimeTrial
var camera_rig: CameraRig
var hud: Hud
var race_hud: RaceHud

var _mode := "race"
var _countdown_left := 0.0
var _countdown_total := 3.0
var _race_over := false

# Dev screenshot hook: APEX_SHOT_DIR=<dir> APEX_SHOT_PLAN="2.0:cockpit,5.0:chase,8.0:top"
# Optional APEX_DRIVE=1 drives the car gently so shots show real action.
var _shot_dir := ""
var _shot_plan: Array = []  # sorted [[time: float, mode: String], ...]
var _shot_timer := 0.0

@onready var debug_overlay: CanvasLayer = $DebugOverlay


func _ready() -> void:
	var mode := OS.get_environment("APEX_MODE")
	if mode == "tt":
		_mode = "tt"
	var text := FileAccess.get_file_as_string(TRACK_PATH)
	track = TrackData.parse(text, TRACK_PATH)
	if track == null:
		push_error("main: cannot parse track %s" % TRACK_PATH)
		return
	var problems := TrackValidator.validate(track)
	if not problems.is_empty():
		push_error("main: track validation failed: %s" % str(problems))
	TrackBuilder.build(track, self)
	_add_environment()

	if _mode == "tt":
		_setup_time_trial()
	else:
		_setup_race()
	debug_overlay.visible = true
	_init_screenshot_hook()


func _add_environment() -> void:
	var packed: PackedScene = load(ENVIRONMENT_MODEL_PATH)
	if packed == null:
		push_warning("main: environment model missing, scenery skipped")
		return
	var scenery := packed.instantiate() as Node3D
	scenery.name = "SceneryEndurance"
	scenery.position = SCENERY_OFFSET
	add_child(scenery)


func _setup_race() -> void:
	var config_text := FileAccess.get_file_as_string(RACE_CONFIG_PATH)
	var config: Dictionary = JSON.parse_string(config_text) as Dictionary
	if config.is_empty():
		push_error("main: cannot parse race config")
		return
	var grid_size: int = config.get("grid_size", 8)
	session = RaceSession.new(track, config, grid_size)
	var grid := session.grid_transforms()

	var ai_cfg: Dictionary = config.get("ai", {})
	var levels: Dictionary = ai_cfg.get("levels", {})
	var default_level: String = ai_cfg.get("default_level", "pro")
	var base_seed: int = ai_cfg.get("seed", 1234)
	var ai_count: int = ai_cfg.get("count", grid_size - 1)
	ai_line = RacingLine.build(track, 2.0, 0.9, 9)
	var vehicle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	)

	for i in range(grid_size):
		var car: Car
		if i == 0:
			car = VehicleFactory.build(AI_COLORS[0], "PlayerCar")
		else:
			car = VehicleFactory.build(AI_COLORS[i % AI_COLORS.size()], "AiCar%d" % i)
		add_child(car)
		car.global_transform = grid[i]
		cars.append(car)
		if i > 0 and i <= ai_count:
			var level: Dictionary = levels.get(default_level, {})
			var profile := SpeedProfile.build(ai_line, vehicle, float(level.get("mu_eff", 0.65)))
			var driver := AiDriver.new()
			add_child(driver)
			driver.setup(car, track, ai_line, profile, level, base_seed + i * 17)
			driver.frozen = true
			drivers.append(driver)
			driver.reset_requested.connect(_on_ai_reset.bind(driver))
	camera_rig = CameraRig.new(cars[0])
	add_child(camera_rig)
	camera_rig.cockpit_camera.current = true

	race_hud = RaceHud.new(cars[0], session, 0)
	add_child(race_hud)
	add_child(TouchControls.new())

	_countdown_total = float(config.get("start", {}).get("countdown_s", 3.0))
	_countdown_left = _countdown_total
	race_hud.show_message("GET READY")


func _setup_time_trial() -> void:
	var car := VehicleFactory.build()
	add_child(car)
	car.global_transform = TrackBuilder.spawn_transform(track)
	tt_session = TimeTrial.new(track)
	camera_rig = CameraRig.new(car)
	add_child(camera_rig)
	camera_rig.cockpit_camera.current = true
	hud = Hud.new(car, tt_session)
	add_child(hud)
	add_child(TouchControls.new())


func _physics_process(delta: float) -> void:
	if _mode == "tt":
		if tt_session != null and not cars.is_empty():
			tt_session.update(cars[0].global_transform.origin, TICK_DT)
		return
	_update_race(delta)


func _update_race(delta: float) -> void:
	if session == null:
		return

		# player input is blocked until the green flag (jump start = no go
		# penalty model yet, phase 7 rules)

		# AI DRS is handled by AiDriver._physics_process
	if not session.started and not _race_over:
		_countdown_left -= delta
		if _countdown_left <= 0.0:
			session.start_race()
			for driver in drivers:
				driver.frozen = false

				# player input is blocked until the green flag (jump start = no go
				# penalty model yet, phase 7 rules)
			cars[0].external_input = null
			race_hud.show_message("GO!")

			# player input is blocked until the green flag (jump start = no go
			# penalty model yet, phase 7 rules)
		else:
			race_hud.show_message(str(ceil(_countdown_left)))
			# player input is blocked until the green flag (jump start = no go
			# penalty model yet, phase 7 rules)
			cars[0].external_input = {
				"throttle": 0.0,
				"brake": 1.0,
				"steer": 0.0,
				"nitro": false,
				"shift_up": false,
				"shift_down": false,
			}

		# AI DRS is handled by AiDriver._physics_process
	var states: Array = []
	for car in cars:
		(
			states
			. append(
				{
					"pos": car.global_transform.origin,
					"forward": -car.global_transform.basis.z,
					"speed": car.linear_velocity.length(),
				}
			)
		)

		# AI DRS is handled by AiDriver._physics_process
	session.update(states, TICK_DT)

	for i in range(cars.size()):
		cars[i].aero_wake_df = session.wake_df(i)
		cars[i].aero_wake_drag = session.wake_drag(i)
		if i == 0:
			_update_player_drs()
			# AI DRS is handled by AiDriver._physics_process
	if not _race_over and not session.classification.is_empty():
		_race_over = true
		var results := "\n".join(session.classification.map(_classification_line))
		race_hud.show_message("FINISH!\n" + results)


func _classification_line(entry: Dictionary) -> String:
	return (
		"P%d  %s  L%d  best %s"
		% [
			entry["position"],
			"YOU" if entry["car_index"] == 0 else "AI%d" % entry["car_index"],
			entry["laps"],
			_format_lap(entry["best_lap"]),
		]
	)


func _update_player_drs() -> void:
	var car := cars[0]
	var available := session.drs_available(0) and session.started and not _race_over
	car.drs_active = (
		available and Input.is_action_pressed("drs") and car.linear_velocity.length() > 1.0
	)


func _on_ai_reset(driver: AiDriver) -> void:
	driver.reset_to_line()


func _process(delta: float) -> void:
	if _shot_plan.is_empty():
		return
	_shot_timer += delta
	while not _shot_plan.is_empty() and _shot_timer >= float(_shot_plan[0][0]):
		var mode: String = _shot_plan.pop_front()[1]
		_capture_shot(mode)


## Runs one scripted lap segment for screenshot/CI visual checks.
func _init_screenshot_hook() -> void:
	_shot_dir = OS.get_environment("APEX_SHOT_DIR")
	if _shot_dir.is_empty():
		return

		# visual QA: drive the player car with a real AI driver so shots
		# show actual racing (not a blind full-throttle crash)
	var plan := OS.get_environment("APEX_SHOT_PLAN")
	for entry in plan.split(","):
		var parts := entry.split(":")
		if parts.size() == 2 and parts[0].is_valid_float():
			_shot_plan.append([parts[0].to_float(), parts[1]])

		# visual QA: drive the player car with a real AI driver so shots
		# show actual racing (not a blind full-throttle crash)
	_shot_plan.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if OS.get_environment("APEX_DRIVE") != "" and not cars.is_empty():
		# visual QA: drive the player car with a real AI driver so shots
		# show actual racing (not a blind full-throttle crash)
		var vehicle: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/data/vehicle.json")
		)
		var race_config: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(RACE_CONFIG_PATH)
		)
		var level: Dictionary = race_config.get("ai", {}).get("levels", {}).get("pro", {})
		var profile := SpeedProfile.build(ai_line, vehicle, float(level.get("mu_eff", 0.65)))
		var driver := AiDriver.new()
		add_child(driver)
		driver.setup(cars[0], track, ai_line, profile, level, 777)
		driver.frozen = not session.started if _mode == "race" else false
		drivers.append(driver)


func _capture_shot(mode: String) -> void:
	var temp_cam: Camera3D = null
	if mode == "chase":
		camera_rig.activate_chase()
	elif mode == "cockpit":
		camera_rig.activate_cockpit()
	elif mode == "top":
		var center := Vector3.ZERO
		for p in track.points:
			center += p
		center /= float(track.point_count())
		temp_cam = Camera3D.new()
		add_child(temp_cam)
		temp_cam.global_position = center + Vector3.UP * 320.0
		temp_cam.look_at(center, Vector3.FORWARD)
		temp_cam.current = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%02d_%s.png" % [_shot_dir, int(_shot_timer), mode]
	img.save_png(path)
	print("screenshot saved: ", path)
	if temp_cam != null:
		temp_cam.queue_free()
	camera_rig.activate_cockpit()
	if _shot_plan.is_empty():
		get_tree().quit()


func _format_lap(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.---"
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes * 60)
	return "%02d:%06.3f" % [minutes, rest]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car()
	elif event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()


## Reset the player car to the nearest centerline point, facing along the track.
func _reset_car() -> void:
	if cars.is_empty() or track == null:
		return
	var n := track.point_count()
	var best_index := 0
	var best_distance := INF
	for i in range(n):
		var distance := track.points[i].distance_to(cars[0].global_transform.origin)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	var dir := track.direction_at(best_index)
	var basis := TrackBuilder.alignment_basis(dir)
	var origin := track.points[best_index] + Vector3.UP * 0.6
	cars[0].reset_to(Transform3D(basis, origin))
