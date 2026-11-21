class_name Phase2Driver
extends Node
## Drives the phase-2 physics scenarios:
## - ai_lap: AiDriver on the full Alpha Loop (track world)
## - aero_clean / aero_wake / aero_drs: scripted full-throttle runs on the
##   flat ground world with a fixed aero context
## - car_collision: two overlapping cars, checks they resolve upright
## Emits done; results land in `report`.

signal done

const TICKS_PER_SECOND := 120

var scenario: String = ""
var duration_ticks: int = 600
var settle_ticks: int = 0
var ticks: int = 0
var report: Dictionary = {}
var telemetry: Array = []

var car: Car
var car_b: Car
var track: TrackData
var ai: AiDriver
var resets: int = 0
var max_off_center: float = 0.0
var laps := 0
var _progress := -1.0
var _max_progress := 0.0


func _physics_process(_delta: float) -> void:
	if scenario == "ai_lap":
		_tick_ai_lap()
	elif scenario == "car_collision":
		_tick_car_collision()
	else:
		_tick_aero()
	ticks += 1
	if ticks >= duration_ticks + settle_ticks:
		set_physics_process(false)
		done.emit()


func _tick_ai_lap() -> void:
	var pos := car.global_transform.origin
	var nearest := 0
	var best := INF
	for i in range(track.point_count()):
		var d: float = track.points[i].distance_to(pos)
		if d < best:
			best = d
			nearest = i
	max_off_center = maxf(max_off_center, best)
	var prog := float(nearest) / float(track.point_count())
	if _progress >= 0.0 and _progress > 0.9 and prog < 0.1 and _max_progress > 0.6:
		laps += 1
		_max_progress = 0.0
	_max_progress = maxf(_max_progress, prog)
	_progress = prog
	telemetry.append(pos)
	if ticks % 240 == 0:
		telemetry.append(car.linear_velocity.length())


func _tick_car_collision() -> void:
	var input := {
		"throttle": 0.0,
		"brake": 1.0,
		"steer": 0.0,
		"nitro": false,
		"shift_up": false,
		"shift_down": false,
	}
	car.external_input = input
	car_b.external_input = input
	if ticks == 0:
		telemetry.append(car.global_transform.origin)
	if ticks % 120 == 0:
		telemetry.append([car.global_transform.origin.y, car_b.global_transform.origin.y])


func _tick_aero() -> void:
	var input := {
		"throttle": 1.0,
		"brake": 0.0,
		"steer": 0.0,
		"nitro": false,
		"shift_up": false,
		"shift_down": false,
	}
	car.external_input = input
	if scenario == "aero_wake":
		car.aero_wake_drag = 1.0
		car.aero_wake_df = 1.0
	elif scenario == "aero_drs":
		car.drs_active = true
	telemetry.append(car.linear_velocity.length())
