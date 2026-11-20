class_name TireModel
extends RefCounted
## Simplified Pacejka "magic formula" tire model (Phase 1 basic version).
## All formulas documented in docs/PHYSICS.md. Stateless: every call takes
## the inputs it needs so tests can exercise it in isolation.


## Lateral force [N] from slip angle.
## Fz: vertical load [N], slip_angle_rad: wheel slip angle [rad],
## mu: tire-road friction coefficient (base, before load sensitivity) [-],
## params: tire constants from vehicle.json ["tires"].
static func lateral_force(fz: float, slip_angle_rad: float, mu: float, params: Dictionary) -> float:
	var b := float(params.get("lat_B", 8.5))
	var c := float(params.get("lat_C", 1.6))
	var effective_mu := _load_sensitive_mu(fz, mu, params, "lat_mu")
	return fz * effective_mu * sin(c * atan(b * slip_angle_rad))


## Longitudinal force [N] from slip ratio.
## slip_ratio: (wheel surface speed - road speed) / max(|road speed|, 1) [-].
static func longitudinal_force(
	fz: float, slip_ratio: float, mu: float, params: Dictionary
) -> float:
	var b := float(params.get("lon_B", 10.0))
	var c := float(params.get("lon_C", 1.65))
	var effective_mu := _load_sensitive_mu(fz, mu, params, "lon_mu")
	return fz * effective_mu * sin(c * atan(b * slip_ratio))


## Load sensitivity: peak mu falls as vertical load grows beyond nominal.
## mu_eff = mu * (1 - sens * (Fz / Fz_nominal - 1)), clamped to [0.3*mu, mu].
static func _load_sensitive_mu(fz: float, mu: float, params: Dictionary, mu_key: String) -> float:
	var sens := float(params.get("load_sensitivity", 0.05))
	var nominal := maxf(float(params.get("nominal_load_n", 2000.0)), 1.0)
	var base_mu := float(params.get(mu_key, mu))
	var ratio := maxf(fz, 0.0) / nominal
	var effective := base_mu * (1.0 - sens * (ratio - 1.0))
	return clampf(effective, 0.3 * base_mu, base_mu)


## Friction circle: combined slip must stay inside mu * Fz. Returns scaled
## [Fx, Fy] pair. Called with forces computed independently for slip ratio
## and slip angle.
static func combine(fx: float, fy: float, fz: float, mu: float) -> Vector2:
	var limit := fz * mu
	if limit <= 0.0:
		return Vector2.ZERO
	var magnitude := sqrt(fx * fx + fy * fy)
	if magnitude <= limit or magnitude < 0.000001:
		return Vector2(fx, fy)
	var scale := limit / magnitude
	return Vector2(fx * scale, fy * scale)
