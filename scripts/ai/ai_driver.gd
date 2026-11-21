class_name AiDriver
extends Node
## Drives a Car along a RacingLine with a SpeedProfile (Phase 2).
## Pure-pursuit steering + reachable-speed controller (brake-limited
## against the profile ahead). Deterministic per seed. The race session
## injects per-tick context: frozen (grid/countdown), drs_available,
## target_offset (overtake side). Emits reset_requested when the car is
## off-track or stuck; the race resets it.

signal reset_requested

const TICK_DT := 1.0 / 120.0
const WHEELBASE_M := 3.1
const V_TOP_MPS := 82.0
const BRAKE_LOOKAHEAD_M := 70.0

var car: Car
var line: RacingLine
var profile: SpeedProfile
var track: TrackData
var difficulty: Dictionary = {}

## race-injected context (defaults keep the driver running free)
var frozen: bool = false
var drs_available: bool = false
var target_offset_m: float = 0.0

var seed_value: int = 0

var _index := 0
var _searched := false
var _steer_cmd := 0.0
var _rng := RandomNumberGenerator.new()
var _offtrack_seconds := 0.0
var _stuck_seconds := 0.0


func setup(
	p_car: Car,
	p_track: TrackData,
	p_line: RacingLine,
	p_profile: SpeedProfile,
	p_difficulty: Dictionary,
	p_seed: int
) -> void:
	car = p_car
	track = p_track
	line = p_line
	profile = p_profile
	difficulty = p_difficulty
	seed_value = p_seed
	_rng.seed = p_seed
	# AI uses the full assist stack except steering assist (it steers itself)
	car.assists_on["auto_gearbox"] = true
	car.assists_on["traction_control"] = true
	car.assists_on["abs"] = true
	car.assists_on["stability_control"] = true
	car.assists_on["steering_assist"] = false


func _physics_process(_delta: float) -> void:
	if car == null or line == null or profile == null:
		return
	var input := {
		"throttle": 0.0,
		"brake": 0.0,
		"steer": 0.0,
		"nitro": false,
		"shift_up": false,
		"shift_down": false,
	}
	if not frozen:
		_update_index()
		var v_fwd := _forward_speed()
		var steer := _steering(v_fwd)
		# the profile already IS the achievable speed at this point (its own
		# backward pass is monotone); re-deriving a windowed limit here jumps
		# non-monotonically and caused late braking into the hairpin
		var target := profile.at(_index) * float(difficulty.get("pace", 1.0))
		var throttle := clampf((target - v_fwd) / 6.0, 0.0, 1.0)
		var brake := clampf((v_fwd - target) * 0.5, 0.0, 1.0)
		# corner power budget: full throttle mid-corner at 25+ m/s trips the
		# traction limit (combined slip); scale throttle by the unused grip
		var mu_eff := float(difficulty.get("mu_eff", 0.95))
		var k_now := absf(line.curvature[_index])
		var a_lat := v_fwd * v_fwd * k_now
		var a_budget := mu_eff * 9.81 * 1.4
		if a_budget > 0.1:
			throttle *= sqrt(clampf(1.0 - a_lat * a_lat / (a_budget * a_budget), 0.0, 1.0))
		if brake > 0.05:
			throttle = 0.0
		input["steer"] = steer
		input["throttle"] = throttle
		input["brake"] = brake
		_recovery_tick(v_fwd)
	car.external_input = input
	# AI opens DRS whenever rules allow; shuts it under braking
	car.drs_active = drs_available and not frozen and input["brake"] < 0.2


func _forward_speed() -> float:
	return maxf(-car.global_transform.basis.z.dot(car.linear_velocity), 0.0)


func _update_index() -> void:
	var n := line.points.size()
	if not _searched:
		_searched = true
		var best := 0
		var best_d := INF
		for i in range(n):
			var d := line.points[i].distance_squared_to(car.global_transform.origin)
			if d < best_d:
				best_d = d
				best = i
		_index = best
		return
	var best := _index
	var best_d := INF
	for off in range(-30, 31):
		var i := (_index + off + n) % n
		var d := line.points[i].distance_squared_to(car.global_transform.origin)
		if d < best_d:
			best_d = d
			best = i
	_index = best


func _steering(v_fwd: float) -> float:
	var n := line.points.size()
	var look_m := clampf(6.0 + v_fwd * 0.7, 6.0, 30.0)
	var i := _index
	var acc := 0.0
	while acc < look_m:
		i = (i + 1) % n
		acc += line.lengths[(i - 1 + n) % n]
	var side := track.side_at(i)
	var target_pos := line.points[i] + side * target_offset_m
	var to_target := target_pos - car.global_transform.origin
	var fwd := -car.global_transform.basis.z
	var right := car.global_transform.basis.x
	var alpha := atan2(to_target.dot(right), to_target.dot(fwd))
	var delta := atan2(2.0 * WHEELBASE_M * sin(alpha), maxf(look_m, 0.5))
	# curvature-envelope cap: never command a tighter radius than ~0.7x the
	# local line radius (pursuit + slip overshoot spiral otherwise)
	var k_line := 0.0
	for off in range(-1, 4):
		k_line = maxf(k_line, absf(line.curvature[(_index + off + n) % n]))
	var r_line := 1.0 / maxf(k_line, 1e-6)
	var delta_line_cap := atan(WHEELBASE_M / maxf(r_line * 0.7, 5.0))
	delta = clampf(delta, -delta_line_cap, delta_line_cap)
	# grip-envelope cap: never command more steer than the lateral budget can
	# hold (bicycle model). Uncapped pursuit demands 0.4 rad at 25 m/s ->
	# 89 m/s^2 -> guaranteed spin. The 1.5 slack covers understeer gradient.
	var mu_eff := float(difficulty.get("mu_eff", 0.95))
	var vehicle: Dictionary = car.data
	var mass := float(vehicle.get("mass_kg", 750.0))
	var aero: Dictionary = vehicle.get("aero", {})
	var c_df := float(aero.get("front_wing_coeff", 0.45)) + float(aero.get("rear_wing_coeff", 0.55))
	var a_cap := mu_eff * (9.81 + c_df * v_fwd * v_fwd / mass) * 1.5
	var delta_cap := atan(a_cap * WHEELBASE_M / maxf(v_fwd * v_fwd, 4.0))
	delta = clampf(delta, -delta_cap, delta_cap)
	var max_steer := car._max_steer_angle(v_fwd)
	var steer := clampf(delta / maxf(max_steer, 0.01), -1.0, 1.0)
	# command slew: full lock in ~0.35 s, kills the correction overshoot
	steer = move_toward(_steer_cmd, steer, 3.0 * TICK_DT)
	_steer_cmd = steer
	var noise := float(difficulty.get("steer_noise", 0.0))
	if noise > 0.0:
		steer = clampf(steer + (_rng.randf() * 2.0 - 1.0) * noise, -1.0, 1.0)
	return steer


## Max speed now such that braking to every profile speed ahead stays feasible.
func _reachable_speed() -> float:
	var n := line.points.size()
	var mu_eff := float(difficulty.get("mu_eff", 0.95))
	var vehicle: Dictionary = car.data
	var mass := float(vehicle.get("mass_kg", 750.0))
	var aero: Dictionary = vehicle.get("aero", {})
	var c_drag := float(aero.get("drag_coeff", 0.48))
	var c_df := float(aero.get("front_wing_coeff", 0.45)) + float(aero.get("rear_wing_coeff", 0.55))
	var limit := V_TOP_MPS
	var dist := 0.0
	var i := _index
	while dist < BRAKE_LOOKAHEAD_M:
		var v_cap := profile.at(i)
		var a_brake := mu_eff * 9.81 + (mu_eff * c_df + c_drag) / mass * v_cap * v_cap
		limit = minf(limit, sqrt(v_cap * v_cap + 2.0 * a_brake * dist))
		dist += line.lengths[i]
		i = (i + 1) % n
	return limit


## Off-track / stuck watchdog: asks the race for a reset.
func _recovery_tick(v_fwd: float) -> void:
	var center_d := track.points[_index].distance_to(car.global_transform.origin)
	var half_width := track.widths[_index] * 0.5
	if center_d > half_width + 6.0:
		_offtrack_seconds += TICK_DT
	else:
		_offtrack_seconds = 0.0
	if v_fwd < 1.5 and not frozen:
		_stuck_seconds += TICK_DT
	else:
		_stuck_seconds = 0.0
	if _offtrack_seconds > 3.0 or _stuck_seconds > 5.0:
		_offtrack_seconds = 0.0
		_stuck_seconds = 0.0
		reset_requested.emit()


## Reset to the nearest line point, facing along the line.
func reset_to_line() -> void:
	_searched = false
	_update_index()
	var dir := track.direction_at(_index)
	var side := track.side_at(_index)
	var origin := line.points[_index] + Vector3.UP * 0.6
	if target_offset_m != 0.0:
		origin += side * clampf(target_offset_m, -4.0, 4.0)
	car.reset_to(Transform3D(TrackBuilder.alignment_basis(dir), origin))
