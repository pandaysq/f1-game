extends Node3D
## Main scene: loads the selected track (race setup 0.6.0), spawns the player
## car + 7 AI cars, runs the offline race session (grid start, countdown,
## positions, DRS rules, aero wake) and wires camera / HUD / touch controls.
## Time Trial (phase 1) stays available: APEX_MODE=tt — with a best-lap ghost
## and track limits. APEX_TRACK env overrides the saved track choice.

const TICK_DT := 1.0 / 120.0
const RACE_CONFIG_PATH := "res://assets/data/race_config.json"
const ENVIRONMENT_MODEL_PATH := "res://assets/models/environment/endurance_run.glb"
## Track margin beyond the road edge that still counts as "on track" (kerbs).
const TRACK_LIMIT_MARGIN_M := 1.5
## The endurance diorama is authored for endurance_run: its own world-space
## road centerline lives in tracks/endurance_run.json, so the scenery stays
## at its authored coordinates. Other tracks run on generated scenery only.
const DIORAMA_TRACK := "endurance_run"

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
var track_id := "endurance_run"
var ai_line: RacingLine
var cars: Array[Car] = []
var drivers: Array[AiDriver] = []
var session: RaceSession
var tt_session: TimeTrial
var camera_rig: CameraRig
var hud: Hud
var race_hud: RaceHud
var pause_menu: PauseMenu
var race_audio: RaceAudio
var nitro_fx: NitroFx
var track_limits := TrackLimits.new()
var ghost_car: GhostCar
var ghost_recorder := GhostRecorder.new()

var _mode := "race"
var _countdown_left := 0.0
var _countdown_total := 3.0
var _lights_shown := 0
var _race_over := false
var _prev_nitro := false

# Dev screenshot hook: APEX_SHOT_DIR=<dir> APEX_SHOT_PLAN="2.0:cockpit,5.0:chase,8.0:top"
# Optional APEX_DRIVE=1 drives the car gently so shots show real action.
var _shot_dir := ""
var _shot_plan: Array = []  # sorted [[time: float, mode: String], ...]
var _shot_timer := 0.0

# Dev telemetry hook: APEX_TRACE=<seconds> prints car/session state every
# second and quits when the timer runs out (headless drive tests).
var _trace_left := 0.0
var _trace_timer := 0.0
var _trace_elapsed := 0.0

@onready var debug_overlay: CanvasLayer = $DebugOverlay


func _ready() -> void:
	Settings.apply_quality()
	_pick_track()
	var mode := OS.get_environment("APEX_MODE")
	if mode.is_empty():
		mode = Settings.launch_mode
	if mode == "tt":
		_mode = "tt"
	var text := FileAccess.get_file_as_string(Settings.track_path(track_id))
	track = TrackData.parse(text, Settings.track_path(track_id))
	if track == null:
		push_error("main: cannot parse track %s" % Settings.track_path(track_id))
		return
	var problems := TrackValidator.validate(track)
	if not problems.is_empty():
		push_error("main: track validation failed: %s" % str(problems))
	TrackBuilder.build(track, self)
	if track_id == DIORAMA_TRACK:
		_add_environment()
	track_limits.cut_committed.connect(_on_cut_committed)
	track_limits.lap_invalidated.connect(_on_lap_invalidated)

	if _mode == "tt":
		_setup_time_trial()
	else:
		_setup_race()
	debug_overlay.visible = OS.get_environment("APEX_DEBUG") == "1"
	_init_screenshot_hook()
	if not OS.get_environment("APEX_TRACE").is_empty():
		_trace_left = maxf(OS.get_environment("APEX_TRACE").to_float(), 1.0)


## Track id: APEX_TRACK env wins (headless/tests), else the race setup choice.
func _pick_track() -> void:
	track_id = OS.get_environment("APEX_TRACK")
	if track_id.is_empty():
		track_id = str(Settings.race.get("track", Settings.DEFAULT_TRACK))
	if Settings.track_path(track_id).is_empty():
		push_warning("main: unknown track '%s', falling back" % track_id)
		track_id = Settings.DEFAULT_TRACK


func _add_environment() -> void:
	var packed: PackedScene = load(ENVIRONMENT_MODEL_PATH)
	if packed == null:
		push_warning("main: environment model missing, scenery skipped")
		return
	var scenery := packed.instantiate() as Node3D
	scenery.name = "SceneryEndurance"
	scenery.position = Vector3.ZERO
	add_child(scenery)
	_add_scenery_collision(scenery)


## The diorama has no collision of its own. Build a static trimesh per mesh so
## the car (and the AI) can drive on the map road; road meshes get asphalt
## grip, everything else is treated as grass/runoff.
func _add_scenery_collision(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var mesh_name := String(mi.name)
			# Grid and finish decals sit above the actual asphalt collision.
			if mesh_name.begins_with("C20-65_") or mesh_name.begins_with("C20-66_"):
				continue
			var road := _is_road_mesh(mesh_name)
			var body := StaticBody3D.new()
			body.name = "MapCollision"
			body.collision_layer = 1
			body.collision_mask = 1
			body.set_meta("grip", 1.0 if road else 0.55)
			body.set_meta("surface", "asphalt" if road else "grass")
			var shape := CollisionShape3D.new()
			shape.shape = mi.mesh.create_trimesh_shape()
			if shape.shape is ConcavePolygonShape3D:
				(shape.shape as ConcavePolygonShape3D).backface_collision = true
			body.add_child(shape)
			mi.add_child(body)
		for child in n.get_children():
			stack.append(child)


func _is_road_mesh(mesh_name: String) -> bool:
	for prefix in ["C20-15_", "C20-16_", "C20-17_", "C20-44_"]:
		if mesh_name.begins_with(prefix):
			return true
	return false


func _setup_race() -> void:
	var config_text := FileAccess.get_file_as_string(RACE_CONFIG_PATH)
	var config: Dictionary = JSON.parse_string(config_text) as Dictionary
	if config.is_empty():
		push_error("main: cannot parse race config")
		return
		# race setup overrides (0.6.0): laps + AI difficulty from Settings.race
	config["laps"] = clampi(int(Settings.race.get("laps", 5)), 1, 99)
	var grid_size: int = config.get("grid_size", 8)
	session = RaceSession.new(track, config, grid_size)
	var grid := session.grid_transforms()

	var ai_cfg: Dictionary = config.get("ai", {})
	var levels: Dictionary = ai_cfg.get("levels", {})
	var default_level := str(Settings.race.get("difficulty", "pro"))
	if not levels.has(default_level):
		default_level = str(ai_cfg.get("default_level", "pro"))
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
	camera_rig.mode_changed.connect(_on_camera_mode_changed)

	race_hud = RaceHud.new(cars[0], session, 0)
	add_child(race_hud)
	race_hud.attach_minimap(track, cars)
	var touch := TouchControls.new()
	add_child(touch)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	touch.pause_pressed.connect(func() -> void: pause_menu.toggle())
	race_audio = RaceAudio.new(cars[0])
	add_child(race_audio)
	nitro_fx = NitroFx.new()
	add_child(nitro_fx)

	_countdown_total = float(config.get("start", {}).get("countdown_s", 3.0))
	_countdown_left = _countdown_total
	_lights_shown = 0
	race_hud.start_lights.show_lights(0)
	race_hud.show_message("GET READY")

	session.lap_completed.connect(_on_race_lap_completed)
	cars[0].body_entered.connect(_on_player_contact)


func _setup_time_trial() -> void:
	var car := VehicleFactory.build()
	add_child(car)
	car.global_transform = TrackBuilder.spawn_transform(track)
	cars.append(car)  # single-car session: keeps _update_* paths uniform
	tt_session = TimeTrial.new(track)
	# racing line feeds the APEX_DRIVE QA driver (ghost/screenshot runs)
	ai_line = RacingLine.build(track, 2.0, 0.9, 9)
	camera_rig = CameraRig.new(car)
	add_child(camera_rig)
	camera_rig.cockpit_camera.current = true
	camera_rig.mode_changed.connect(_on_camera_mode_changed)
	hud = Hud.new(car, tt_session)
	add_child(hud)
	hud.attach_context(track, track_limits)
	var touch := TouchControls.new()
	add_child(touch)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	touch.pause_pressed.connect(func() -> void: pause_menu.toggle())
	race_audio = RaceAudio.new(car)
	add_child(race_audio)
	nitro_fx = NitroFx.new()
	add_child(nitro_fx)

	ghost_car = GhostCar.new()
	add_child(ghost_car)
	var ghost := GhostRecorder.load_best(track.track_name)
	if not ghost.is_empty():
		ghost_car.play_recording(ghost)
	tt_session.lap_completed.connect(_on_tt_lap_completed)
	car.body_entered.connect(_on_player_contact)


func _physics_process(delta: float) -> void:
	if _mode == "tt":
		if tt_session != null and not cars.is_empty():
			tt_session.update(cars[0].global_transform.origin, TICK_DT)
			_update_feedback(TICK_DT)
			_update_ghost_recording(TICK_DT)
		return
	_update_race(delta)


func _update_race(delta: float) -> void:
	if session == null:
		return

		# player input is blocked until the green flag (jump start = no go
		# penalty model yet, phase 7 rules); AI DRS is handled by AiDriver
	if not session.started and not _race_over:
		_countdown_left -= delta
		var step := _countdown_total / 5.0
		var elapsed := _countdown_total - _countdown_left
		var lights := clampi(1 + int(elapsed / step), 0, 5)
		if lights != _lights_shown:
			_lights_shown = lights
			Sfx.start_light()
		race_hud.start_lights.show_lights(lights)
		if _countdown_left <= 0.0:
			session.start_race()
			for driver in drivers:
				driver.frozen = false
			cars[0].external_input = null
			race_hud.start_lights.lights_out()
			Sfx.lights_out()
			Vibration.green_flag()
			race_hud.show_message("GO!")
		else:
			race_hud.show_message(str(ceil(_countdown_left)))
			cars[0].external_input = {
				"throttle": 0.0,
				"brake": 1.0,
				"steer": 0.0,
				"nitro": false,
				"shift_up": false,
				"shift_down": false,
			}
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
	session.update(states, TICK_DT)

	for i in range(cars.size()):
		cars[i].aero_wake_df = session.wake_df(i)
		cars[i].aero_wake_drag = session.wake_drag(i)
		if i == 0:
			_update_player_drs()
	_update_feedback(TICK_DT)
	_update_track_limits(TICK_DT)
	if not _race_over and not session.classification.is_empty():
		_race_over = true
		Sfx.finish()
		race_hud.show_results(session.classification)
		_record_career()
		print("[race] classified, career recorded")


## Shared per-tick feedback: nitro fx + camera shake + haptic edges.
func _update_feedback(delta: float) -> void:
	if cars.is_empty() or camera_rig == null:
		return
	var car := cars[0]
	var speed := car.linear_velocity.length()
	camera_rig.shake_level = 1.0 if car.nitro_active else 0.0
	if nitro_fx != null:
		nitro_fx.set_state(car.nitro_active, speed, delta)
	if car.nitro_active and not _prev_nitro:
		Vibration.nitro_pulse()
	_prev_nitro = car.nitro_active


## Track-limits: measures the player against the road edge (road + margin).
func _update_track_limits(delta: float) -> void:
	if track == null or cars.is_empty():
		return
	var progress := 0.0
	if _mode == "tt" and tt_session != null:
		progress = tt_session.progress()
	elif session != null and not session.progress.is_empty():
		progress = maxf(session.progress[0], 0.0)
	var n := track.point_count()
	var idx := clampi(int(progress * float(n)), 0, n - 1)
	var half := track.widths[idx] * 0.5 + TRACK_LIMIT_MARGIN_M
	var off := cars[0].global_transform.origin.distance_to(track.points[idx]) > half
	track_limits.update(off, cars[0].linear_velocity.length(), delta)


func _update_ghost_recording(delta: float) -> void:
	if cars.is_empty() or ghost_car == null:
		return
	var car := cars[0]
	var fwd := -car.global_transform.basis.z
	ghost_recorder.record(
		tt_session.current_lap_time, car.global_transform.origin, atan2(-fwd.x, -fwd.z), delta
	)


func _on_tt_lap_completed(lap_time: float, is_best: bool) -> void:
	track_limits.reset_lap()
	if not is_best or not track_limits.lap_valid():
		return
	var samples := ghost_recorder.finish_lap()
	if GhostRecorder.save_best(track.track_name, lap_time, samples):
		ghost_car.play_recording(samples)


func _on_race_lap_completed(car_index: int, _lap_time: float) -> void:
	if car_index == 0:
		track_limits.reset_lap()


func _on_cut_committed(count: int) -> void:
	if race_hud != null:
		race_hud.show_track_limits(count)
	elif hud != null:
		hud.show_message("TRACK LIMITS %d/%d" % [count, TrackLimits.LIMITS_PER_LAP])


func _on_lap_invalidated(count: int) -> void:
	if race_hud != null:
		race_hud.show_track_limits(count, true)
	if hud != null:
		hud.show_invalid_lap()


func _on_player_contact(_body: Node) -> void:
	if cars.is_empty():
		return
	var speed := cars[0].linear_velocity.length()
	if speed < 5.0:
		return
	var strength := clampf(speed / 30.0, 0.2, 1.0)
	if camera_rig != null:
		camera_rig.add_shake_impulse(strength)
	Vibration.crash(strength)


## Career-lite: persist the finished race result (player only, 0.6.0).
func _record_career() -> void:
	for entry in session.classification:
		if int(entry.get("car_index", -1)) != 0:
			continue
		CareerStore.record_race(
			track_id,
			"race",
			int(entry.get("position", 99)),
			session.car_count,
			float(entry.get("best_lap", -1.0)),
			session.total_laps
		)
		return


func _update_player_drs() -> void:
	var car := cars[0]
	var available := session.drs_available(0) and session.started and not _race_over
	car.drs_active = (
		available and Input.is_action_pressed("drs") and car.linear_velocity.length() > 1.0
	)


func _on_ai_reset(driver: AiDriver) -> void:
	driver.reset_to_line()


func _on_camera_mode_changed(label: String) -> void:
	Sfx.select()
	if race_hud != null:
		race_hud.show_message("CAMERA: " + label)
	elif hud != null:
		hud.show_message("CAMERA: " + label)


func _process(delta: float) -> void:
	if _trace_left > 0.0:
		_trace_left -= delta
		_trace_timer += delta
		_trace_elapsed += delta
		if _trace_timer >= 1.0:
			_trace_timer = 0.0
			_print_trace()
		if _trace_left <= 0.0:
			get_tree().quit()
	if _shot_plan.is_empty():
		return
	_shot_timer += delta
	while not _shot_plan.is_empty() and _shot_timer >= float(_shot_plan[0][0]):
		var mode: String = _shot_plan.pop_front()[1]
		_capture_shot(mode)


## Dev telemetry: one line per car with speed, nearest centerline index and
## how far it is from the centerline. Used by headless drive tests (race + tt).
func _print_trace() -> void:
	if session == null and tt_session == null:
		return
	var laps := 0
	var running := false
	if session != null:
		running = session.started
		if not session.laps_completed.is_empty():
			laps = session.laps_completed[0]
	elif tt_session != null:
		running = true
		laps = tt_session.lap_count
	var parts: Array[String] = []
	for i in range(cars.size()):
		var car := cars[i]
		var pos := car.global_transform.origin
		var best_i := 0
		var best_d := INF
		for j in range(track.point_count()):
			var d := pos.distance_squared_to(track.points[j])
			if d < best_d:
				best_d = d
				best_i = j
		var lap_str := ""
		if session != null and i < session.laps_completed.size():
			lap_str = " lap=%d" % session.laps_completed[i]
		(
			parts
			. append(
				(
					"%d:%s v=%.1f idx=%d off=%.1f y=%.2f%s"
					% [
						i,
						"P" if i == 0 else "AI",
						car.linear_velocity.length() * 3.6,
						best_i,
						sqrt(best_d),
						pos.y,
						lap_str,
					]
				)
			)
		)
	print(
		(
			"[trace] t=%.1f started=%s laps=%d %s"
			% [_trace_elapsed, str(running), laps, " | ".join(parts)]
		)
	)


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
	_shot_plan.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if OS.get_environment("APEX_DRIVE") != "" and not cars.is_empty():
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
	elif mode == "tcam":
		camera_rig.activate_t_cam()
	elif mode == "tv":
		camera_rig.activate_tv()
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car()

		# pause (ui_cancel / pause_game) is owned by PauseMenu
	elif event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible


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
