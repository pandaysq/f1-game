class_name CameraRig
extends Node3D
## Cockpit camera (primary, FPV from driver seat) + chase camera (debug, V).
## Cockpit follows the chassis rigidly; chase camera is spring-smoothed.

const CHASE_OFFSET_LOCAL := Vector3(0.0, 1.1, 3.8)
## Driver-eye position in car-local space (origin = wheel attach plane).
## Calibrated on the glb cockpit: eye under the halo, wing mirror in view,
## nose clearly visible. Tuning helper: APEX_COCKPIT_OVERRIDE="x,y,z".
const COCKPIT_LOCAL := Vector3(-0.22, 0.52, 0.20)

var cockpit_camera: Camera3D
var chase_camera: Camera3D

var _car: Car


func _init(car: Car) -> void:
	_car = car

	cockpit_camera = Camera3D.new()
	cockpit_camera.name = "CockpitCamera"
	# driver eyes: under the glb halo pod (pod spans y 0.59..0.71 above the
	# attach plane, cockpit sits ~0.3 m behind the axle midpoint)
	cockpit_camera.position = COCKPIT_LOCAL
	var override := OS.get_environment("APEX_COCKPIT_OVERRIDE")
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 3:
			cockpit_camera.position = Vector3(
				parts[0].to_float(), parts[1].to_float(), parts[2].to_float()
			)
	cockpit_camera.fov = 78.0
	cockpit_camera.near = 0.05
	add_child(cockpit_camera)

	chase_camera = Camera3D.new()
	chase_camera.name = "ChaseCamera"
	chase_camera.fov = 70.0
	add_child(chase_camera)

	cockpit_camera.current = true


func activate_cockpit() -> void:
	cockpit_camera.current = true


func activate_chase() -> void:
	if not chase_camera.current:
		chase_camera.current = true
		_snap_chase()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		if cockpit_camera.current:
			activate_chase()
		else:
			activate_cockpit()


func _snap_chase() -> void:
	chase_camera.global_transform = _desired_chase_transform()


func _physics_process(_delta: float) -> void:
	# rig rides the car: cockpit camera is car-local, chase camera overrides
	# its own global transform explicitly below (parent transform is ignored)
	global_transform = _car.global_transform
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
