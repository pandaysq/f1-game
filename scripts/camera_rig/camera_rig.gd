class_name CameraRig
extends Node3D
## Camera set: cockpit (driver eye), T-cam (roll-hoop onboard), chase and TV.
## Cockpit/T-cam ride the chassis rigidly; chase/TV are spring-smoothed.
## V cycles the cameras.

signal mode_changed(label: String)

enum Mode { COCKPIT, T_CAM, CHASE, TV }

const MODE_LABELS := ["COCKPIT", "T-CAM", "CHASE", "TV"]

## Driver-eye position in car-local space (origin = wheel attach plane).
## Calibrated against the glb cockpit: eye behind the halo centre pillar,
## above the rim, both mirrors at the frame edges. Tuning helper:
## APEX_COCKPIT_OVERRIDE="x,y,z".
const COCKPIT_LOCAL := Vector3(0.0, 0.60, -0.10)
const COCKPIT_PITCH := deg_to_rad(-3.0)
## Roll-hoop onboard camera, just above the airbox.
const T_CAM_LOCAL := Vector3(0.0, 0.98, 0.12)
const CHASE_OFFSET_LOCAL := Vector3(0.0, 1.8, 5.6)
const CHASE_AIM_LOCAL := Vector3(0.0, 0.5, -1.8)
const TV_OFFSET_LOCAL := Vector3(3.2, 3.4, 8.5)
const TV_AIM_LOCAL := Vector3(0.0, 0.5, 0.0)

var cockpit_camera: Camera3D
var t_cam: Camera3D
var chase_camera: Camera3D
var tv_camera: Camera3D

var _car: Car
var _mode: int = Mode.COCKPIT


func _init(car: Car) -> void:
	_car = car

	cockpit_camera = _make_camera("CockpitCamera", COCKPIT_LOCAL, 78.0, 0.05)
	cockpit_camera.rotation.x = COCKPIT_PITCH
	var override := OS.get_environment("APEX_COCKPIT_OVERRIDE")
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 3:
			cockpit_camera.position = Vector3(
				parts[0].to_float(), parts[1].to_float(), parts[2].to_float()
			)

	t_cam = _make_camera("TCam", T_CAM_LOCAL, 70.0, 0.05)
	chase_camera = _make_camera("ChaseCamera", Vector3.ZERO, 70.0, 0.10)
	tv_camera = _make_camera("TvCamera", Vector3.ZERO, 58.0, 0.20)
	chase_camera.top_level = true
	tv_camera.top_level = true

	_set_mode(Mode.COCKPIT, false)


func _make_camera(camera_name: String, pos: Vector3, fov: float, near: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = camera_name
	cam.position = pos
	cam.fov = fov
	cam.near = near
	add_child(cam)
	return cam


func current_mode_label() -> String:
	return MODE_LABELS[_mode]


func activate_cockpit() -> void:
	_set_mode(Mode.COCKPIT)


func activate_chase() -> void:
	_set_mode(Mode.CHASE)


func activate_t_cam() -> void:
	_set_mode(Mode.T_CAM)


func activate_tv() -> void:
	_set_mode(Mode.TV)


func _set_mode(mode: int, announce: bool = true) -> void:
	_mode = mode
	cockpit_camera.current = mode == Mode.COCKPIT
	t_cam.current = mode == Mode.T_CAM
	chase_camera.current = mode == Mode.CHASE
	tv_camera.current = mode == Mode.TV
	if mode == Mode.CHASE:
		_snap(chase_camera, _follow_transform(CHASE_OFFSET_LOCAL, CHASE_AIM_LOCAL))
	elif mode == Mode.TV:
		_snap(tv_camera, _follow_transform(TV_OFFSET_LOCAL, TV_AIM_LOCAL))
	if announce:
		mode_changed.emit(MODE_LABELS[_mode])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_set_mode((_mode + 1) % MODE_LABELS.size())


func _snap(camera: Camera3D, target: Transform3D) -> void:
	camera.global_transform = target


func _physics_process(delta: float) -> void:
	global_transform = _car.global_transform
	var speed := _car.linear_velocity.length()
	var kick := clampf(speed / 90.0, 0.0, 1.0)

	match _mode:
		Mode.COCKPIT:
			cockpit_camera.fov = lerpf(78.0, 88.0, kick)
		Mode.T_CAM:
			t_cam.fov = lerpf(70.0, 80.0, kick)
		Mode.CHASE:
			_spring(chase_camera, CHASE_OFFSET_LOCAL, CHASE_AIM_LOCAL, 12.0, delta)
		Mode.TV:
			_spring(tv_camera, TV_OFFSET_LOCAL, TV_AIM_LOCAL, 7.0, delta)


func _spring(camera: Camera3D, offset: Vector3, aim: Vector3, rate: float, delta: float) -> void:
	var desired := _follow_transform(offset, aim)
	var weight := 1.0 - exp(-rate * delta)
	var origin := camera.global_position.lerp(desired.origin, weight)
	var target := _car.to_global(aim)
	if origin.distance_squared_to(target) < 0.25:
		origin = desired.origin
	camera.global_transform = Transform3D(Basis.IDENTITY, origin).looking_at(target, Vector3.UP)


func _follow_transform(offset: Vector3, aim: Vector3) -> Transform3D:
	var origin := _car.to_global(offset)
	return Transform3D(Basis.IDENTITY, origin).looking_at(_car.to_global(aim), Vector3.UP)
