class_name CameraRig
extends Node3D
## Cockpit camera (primary, FPV from driver seat) + chase camera (debug, V).
## Cockpit follows the chassis rigidly; chase camera is spring-smoothed.

const CHASE_OFFSET_LOCAL := Vector3(0.0, 1.1, 3.8)

var cockpit_camera: Camera3D
var chase_camera: Camera3D

var _car: Car


func _init(car: Car) -> void:
	_car = car

	cockpit_camera = Camera3D.new()
	cockpit_camera.name = "CockpitCamera"
	# driver eyes: slightly above attach plane (CG offset ~0.3 below origin)
	cockpit_camera.position = Vector3(-0.35, 0.28, -0.35)
	cockpit_camera.fov = 78.0
	cockpit_camera.near = 0.05
	add_child(cockpit_camera)

	chase_camera = Camera3D.new()
	chase_camera.name = "ChaseCamera"
	chase_camera.fov = 70.0
	add_child(chase_camera)

	cockpit_camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		var cockpit_active := cockpit_camera.current
		cockpit_camera.current = not cockpit_active
		if not cockpit_active:
			_snap_chase()


func _snap_chase() -> void:
	chase_camera.global_transform = _desired_chase_transform()


func _physics_process(_delta: float) -> void:
	# FOV kick for speed feeling (cockpit only)
	var speed := _car.linear_velocity.length()
	var kick := clampf(speed / 90.0, 0.0, 1.0)
	cockpit_camera.fov = lerpf(78.0, 88.0, kick)

	if not chase_camera.current:
		return
	var desired := _desired_chase_transform()
	var weight := 1.0 - exp(-8.0 * _physics_delta())
	chase_camera.global_transform = chase_camera.global_transform.interpolate_with(desired, weight)


func _desired_chase_transform() -> Transform3D:
	var car_transform := _car.global_transform
	var offset := car_transform.basis * CHASE_OFFSET_LOCAL
	var look_target := car_transform.origin + car_transform.basis * Vector3(0, 0.4, -6)
	var origin := car_transform.origin + offset
	var forward := (look_target - origin).normalized()
	var basis := Basis(-forward.cross(Vector3.UP).normalized(), Vector3.UP, forward)
	return Transform3D(basis, origin)


func _physics_delta() -> float:
	return 1.0 / 60.0
