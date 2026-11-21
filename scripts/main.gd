extends Node3D
## Phase 1 main scene: builds Alpha Loop track, spawns the player car,
## runs the Time Trial session and wires camera / HUD / touch controls.

const TICK_DT := 1.0 / 120.0
const TRACK_PATH := "res://tracks/alpha_loop.json"

var car: Car
var track: TrackData
var session: TimeTrial
var camera_rig: CameraRig

# Dev screenshot hook: APEX_SHOT_DIR=<dir> APEX_SHOT_PLAN="2.0:cockpit,5.0:chase,8.0:top"
# Optional APEX_DRIVE=1 drives the car gently so shots show real action.
var _shot_dir := ""
var _shot_plan: Array = []  # sorted [[time: float, mode: String], ...]
var _shot_timer := 0.0

@onready var debug_overlay: CanvasLayer = $DebugOverlay


func _ready() -> void:
	var text := FileAccess.get_file_as_string(TRACK_PATH)
	track = TrackData.parse(text, TRACK_PATH)
	if track == null:
		push_error("main: cannot parse track %s" % TRACK_PATH)
		return
	var problems := TrackValidator.validate(track)
	if not problems.is_empty():
		push_error("main: track validation failed: %s" % str(problems))
	TrackBuilder.build(track, self)

	car = VehicleFactory.build()
	add_child(car)
	car.global_transform = TrackBuilder.spawn_transform(track)

	session = TimeTrial.new(track)

	camera_rig = CameraRig.new(car)
	add_child(camera_rig)
	camera_rig.cockpit_camera.current = true

	add_child(Hud.new(car, session))
	add_child(TouchControls.new())

	debug_overlay.visible = true
	_init_screenshot_hook()


## Runs one scripted lap segment for screenshot/CI visual checks.
func _init_screenshot_hook() -> void:
	_shot_dir = OS.get_environment("APEX_SHOT_DIR")
	if _shot_dir.is_empty():
		return

	var plan := OS.get_environment("APEX_SHOT_PLAN")
	for entry in plan.split(","):
		var parts := entry.split(":")
		if parts.size() == 2 and parts[0].is_valid_float():
			_shot_plan.append([parts[0].to_float(), parts[1]])

	_shot_plan.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if OS.get_environment("APEX_DRIVE") != "":
		car.external_input = {
			"throttle": 1.0,
			"brake": 0.0,
			"steer": 0.0,
			"nitro": false,
			"shift_up": false,
			"shift_down": false
		}


func _process(delta: float) -> void:
	if _shot_plan.is_empty():
		return
	_shot_timer += delta
	while not _shot_plan.is_empty() and _shot_timer >= float(_shot_plan[0][0]):
		var mode: String = _shot_plan.pop_front()[1]
		_capture_shot(mode)


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


func _physics_process(_delta: float) -> void:
	if session != null and car != null:
		session.update(car.global_transform.origin, TICK_DT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car()
	elif event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()


## Reset the car to the nearest centerline point, facing along the track.
func _reset_car() -> void:
	if car == null or track == null:
		return
	var n := track.point_count()
	var best_index := 0
	var best_distance := INF
	for i in range(n):
		var distance := track.points[i].distance_to(car.global_transform.origin)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	var dir := track.direction_at(best_index)
	var basis := TrackBuilder.alignment_basis(dir)
	var origin := track.points[best_index] + Vector3.UP * 0.6
	car.reset_to(Transform3D(basis, origin))
