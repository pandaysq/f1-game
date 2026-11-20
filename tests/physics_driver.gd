class_name PhysicsTestDriver
extends Node
## Drives a Car through a scripted input scenario, collecting per-tick
## telemetry. Tick-based (not time-based) so results are independent of
## Engine.time_scale. Used only by tests.

signal done

const TICKS_PER_SECOND := 120

var car: Car
var scenario: String = ""
var duration_ticks: int = 600
var settle_ticks: int = 60
var ticks: int = 0
var telemetry: Array = []  # {pos, vel, speed} per physics tick


func _physics_process(_delta: float) -> void:
	var input := {
		"throttle": 0.0,
		"brake": 0.0,
		"steer": 0.0,
		"nitro": false,
		"shift_up": false,
		"shift_down": false,
	}
	var active := ticks - settle_ticks
	if scenario == "accel" or scenario == "accel_det":
		if active >= 0:
			input["throttle"] = 1.0
	elif scenario == "accel_brake":
		if active >= 0 and active < 22 * TICKS_PER_SECOND:
			input["throttle"] = 1.0
		elif active >= 22 * TICKS_PER_SECOND:
			input["brake"] = 1.0
	elif scenario == "steer_left":
		if active >= 0:
			input["throttle"] = 1.0
			input["steer"] = -1.0
	elif scenario == "steer_right":
		if active >= 0:
			input["throttle"] = 1.0
			input["steer"] = 1.0
	# "no_free_speed" keeps zero input
	car.external_input = input

	(
		telemetry
		. append(
			{
				"pos": car.global_transform.origin,
				"vel": car.linear_velocity,
				"speed": car.linear_velocity.length(),
			}
		)
	)

	ticks += 1
	if ticks >= duration_ticks + settle_ticks:
		done.emit()
		set_physics_process(false)
