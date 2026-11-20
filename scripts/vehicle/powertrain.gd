class_name Powertrain
extends RefCounted
## Engine + gearbox (Phase 1): torque curve, 8 gears + reverse, shift time,
## rev limiter. Data-driven from assets/data/vehicle.json.

var gear: int = 1  # 0 = reverse (R), 1..8 forward
var rpm: float = 3000.0
var shifting_until: float = 0.0  # sim time until which torque is cut

var _engine: Dictionary
var _gearbox: Dictionary
var _torque_curve: Array = []  # [ [rpm, Nm], ... ]


func _init(data: Dictionary) -> void:
	_engine = data.get("engine", {})
	_gearbox = data.get("gearbox", {})
	_torque_curve = _engine.get("torque_curve_nm", [[3000, 320.0], [13000, 330.0]])


## Engine output torque [Nm] at crank for current rpm and throttle [0..1].
## Cut while shifting or past redline (limiter). Direction (reverse) is
## handled by the gearbox ratio sign.
func output_torque(throttle: float, sim_time: float) -> float:
	if sim_time < shifting_until:
		return 0.0
	if rpm >= redline_rpm():
		return 0.0
	return torque_at(rpm) * clampf(throttle, 0.0, 1.0)


## Torque [Nm] interpolated from the curve (values are positive).
func torque_at(rpm_value: float) -> float:
	var curve := _torque_curve
	if curve.is_empty():
		return 0.0
	if rpm_value <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var rpm_hi := float(curve[i][0])
		if rpm_value <= rpm_hi:
			var rpm_lo := float(curve[i - 1][0])
			var t_lo := float(curve[i - 1][1])
			var t_hi := float(curve[i][1])
			var t := (rpm_value - rpm_lo) / maxf(rpm_hi - rpm_lo, 1.0)
			return lerpf(t_lo, t_hi, t)
	return float(curve[curve.size() - 1][1])


## Wheel drive torque [Nm] on each driven wheel (rear axle, two wheels).
## negative when reversing. Includes final drive.
func wheel_torque(sim_time: float, throttle: float) -> float:
	var ratio := _current_ratio()
	return output_torque(throttle, sim_time) * ratio * final_drive() * 0.5


## Update rpm from driven wheel angular speed [rad/s] (with clutch slip at
## low speed so the car can launch). Should be called before torque queries.
func update_rpm(wheel_angular_speed: float, throttle: float) -> void:
	var ratio := _current_ratio()
	var wheel_rpm := absf(wheel_angular_speed) * ratio * final_drive() * 60.0 / TAU
	rpm = maxf(wheel_rpm, float(_engine.get("idle_rpm", 3000.0)))
	var launch := float(_engine.get("launch_rpm", 7000.0))
	# slipping clutch approximation while launching (uses throttle)
	rpm = maxf(rpm, minf(launch, idle_rpm() + throttle * launch))
	rpm = minf(rpm, redline_rpm() * 1.02)


func request_shift(direction: int, sim_time: float) -> void:
	var low := 0  # reverse
	var high := _ratios().size()
	var target := gear + direction
	if target < low or target > high:
		return
	gear = target
	shifting_until = sim_time + shift_time()


func auto_shift(wheel_angular_speed: float, _throttle: float, sim_time: float) -> void:
	if sim_time < shifting_until:
		return
	if gear == 0:
		return  # no auto shifts from reverse
	var ratio := _current_ratio()
	var wheel_rpm := absf(wheel_angular_speed) * ratio * final_drive() * 60.0 / TAU
	var red := redline_rpm()
	if (
		wheel_rpm >= red * float(_gearbox.get("upshift_rpm_fraction", 0.94))
		and gear < _ratios().size()
	):
		request_shift(1, sim_time)
	elif wheel_rpm <= red * float(_gearbox.get("downshift_rpm_fraction", 0.55)) and gear > 1:
		request_shift(-1, sim_time)


func _current_ratio() -> float:
	if _in_reverse():
		return float(_gearbox.get("reverse_ratio", -2.8))
	var ratios := _ratios()
	return float(ratios[gear - 1])


func _in_reverse() -> bool:
	return gear == 0


func _ratios() -> Array:
	return _gearbox.get("ratios", [3.2])


func final_drive() -> float:
	return float(_gearbox.get("final_drive", 3.4))


func shift_time() -> float:
	return float(_gearbox.get("shift_time_s", 0.15))


func idle_rpm() -> float:
	return float(_engine.get("idle_rpm", 3000.0))


func redline_rpm() -> float:
	return float(_engine.get("redline_rpm", 13000.0))
