class_name SpeedProfile
extends RefCounted
## Target speed per racing-line point (Phase 2). Deterministic, pure data.
##
## 1. Corner speeds: per-axle tire caps with aero downforce — closed form,
##    because both the lateral demand (v^2 * k) and the tire cap (mu * (g*share
##    + c_axle * v^2 / m)) are linear in v^2:
##        v^2 * k = mu * (g * share + c_axle * v^2 / m) / share
##        -> v^2 = A / (k - B)
## 2. Backward pass: braking deceleration grows with v (aero drag + downforce).
## 3. Forward pass: power-limited acceleration, capped by rear-tire traction.
##
## mu_eff is an effective friction scale (NOT the raw tire mu): it is
## calibrated against the simulated car's demonstrated braking/cornering
## (see docs/PHYSICS.md), and doubles as the AI difficulty knob.

var speeds: Array[float] = []  # target speed at line point [m/s]
var lengths: Array[float] = []  # distance to next point [m] (from the line)


## Build the profile. vehicle = parsed assets/data/vehicle.json dictionary.
static func build(
	line: RacingLine,
	vehicle: Dictionary,
	mu_eff: float,
	v_top: float = 82.0,
	power_w: float = 350000.0,
	corner_safety: float = 0.96,
	brake_mu_eff: float = 1.05,
	drive_mu_eff: float = 1.0
) -> SpeedProfile:
	var n := line.points.size()
	var profile := SpeedProfile.new()
	profile.lengths = line.lengths
	var mass := float(vehicle.get("mass_kg", 750.0))
	var w_f := float(vehicle.get("weight_distribution_front", 0.45))
	var aero: Dictionary = vehicle.get("aero", {})
	var c_fw := float(aero.get("front_wing_coeff", 0.45))
	var c_rw := float(aero.get("rear_wing_coeff", 0.55))
	var c_drag := float(aero.get("drag_coeff", 0.48))
	var c_df := c_fw + c_rw

	# corner limits per point (from the racing line's own curvature)
	var curvature := RacingLine._curvature(line.points)
	profile.speeds.resize(n)
	for i in range(n):
		var k := absf(curvature[i])
		profile.speeds[i] = v_top
		if k > 0.00005:
			# front axle cap: lateral share on front = 1 - w_f
			var a_f := mu_eff * 9.81 * w_f / (1.0 - w_f)
			var b_f := mu_eff * c_fw / (mass * (1.0 - w_f))
			# rear axle cap: lateral share on rear = w_f
			var a_r := mu_eff * 9.81 * (1.0 - w_f) / w_f
			var b_r := mu_eff * c_rw / (mass * w_f)
			var v_f := a_f / maxf(k - b_f, 0.00001)
			var v_r := a_r / maxf(k - b_r, 0.00001)
			if k > b_f:
				profile.speeds[i] = minf(profile.speeds[i], sqrt(v_f) * corner_safety)
			if k > b_r:
				profile.speeds[i] = minf(profile.speeds[i], sqrt(v_r) * corner_safety)
	# backward pass (twice around the loop to converge through the wrap).
	# Braking is calibrated SEPARATELY from cornering: the sim car brakes at
	# ~16 m/s^2 from 300 km/h (phase-1 measured 190 m), which is mu ~1.35
	# with downforce — cornering mu_eff is NOT the braking limit.
	for _lap in range(2):
		for i in range(n - 2, -1, -1):
			var next_speed := profile.speeds[(i + 1) % n]
			var a_brake := (
				brake_mu_eff * (9.81 + c_df * next_speed * next_speed / mass)
				+ c_drag * next_speed * next_speed / mass
			)
			var reach := sqrt(next_speed * next_speed + 2.0 * a_brake * line.lengths[i])
			profile.speeds[i] = minf(profile.speeds[i], reach)
	# forward pass (twice around: grid starts need accel from low speed)
	for _lap in range(2):
		for i in range(n):
			var next_i := (i + 1) % n
			var v := maxf(profile.speeds[i], 2.0)
			var power_cap := power_w / (mass * maxf(v, 8.0))
			var traction_cap := drive_mu_eff * (9.81 * (1.0 - w_f) + c_rw * v * v / mass)
			var a_drive := minf(power_cap, traction_cap)
			var reach := sqrt(v * v + 2.0 * a_drive * line.lengths[i])
			profile.speeds[next_i] = minf(profile.speeds[next_i], reach)
	return profile


## Target speed at a line point [m/s].
func at(index: int) -> float:
	if speeds.is_empty():
		return 0.0
	return speeds[index % speeds.size()]


## Smallest target speed within [from, to] indices along the line (wrapped).
## Used by the driver to look ahead for brake points.
func min_between(from: int, to: int) -> float:
	var n := speeds.size()
	if n == 0:
		return 0.0
	var worst := speeds[from % n]
	var steps := (to - from) % n
	for k in range(1, steps + 1):
		worst = minf(worst, speeds[(from + k) % n])
	return worst
