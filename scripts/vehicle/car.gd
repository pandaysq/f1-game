class_name Car
extends RigidBody3D
## Open-wheel car physics (Phase 1): custom raycast-suspension vehicle.
##
## Emitted when R (reset) was requested and the car needs a track reference.
signal reset_requested
## Body origin sits at wheel-attach plane height; center of mass is offset
## down per vehicle.json. Fixed 120 Hz tick. All constants come from
## assets/data/vehicle.json. See docs/PHYSICS.md for formulas and units.

const TICK_DT := 1.0 / 120.0
const KERB_DECAY_PER_S := 3.0

## Set by tests / replay code to drive the car deterministically.
## Dictionary with keys: throttle, brake, steer [-1..1], nitro, shift_up,
## shift_down. When non-null, real input is ignored.
var external_input: Variant = null

## Aero context (Phase 2), set each tick by the race session or tests:
## - aero_wake_df   0..1 dirty air depth (short range) -> downforce loss
## - aero_wake_drag  0..1 slipstream depth (long range) -> drag cut
## - drs_active     rear wing flap open (activation rules live in race config)
## Defaults keep Phase 1 clean-air behaviour (all zero).
var aero_wake_df: float = 0.0
var aero_wake_drag: float = 0.0
var drs_active: bool = false

## Last gathered input dict — audio/HUD read what the driver actually asked
## for (nitro state lives here for touch and keyboard alike).
var last_input: Dictionary = {}
## Nitro boost (0.5.0): thrust while held and the tank has charge; the tank
## drains while boosting and refills while idle. Data: vehicle.json "nitro".
var nitro_active: bool = false
var nitro_left: float = 0.0

var data: Dictionary = {}
var powertrain: Powertrain
var assists_on: Dictionary = {}

var sim_time: float = 0.0
var steering_angle: float = 0.0
var wheel_spin: Array[float] = [0.0, 0.0, 0.0, 0.0]  # FL FR RL RR [rad/s]
var wheel_contacts: Array[bool] = [false, false, false, false]
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_slip_ratios: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_slip_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_fx: Array[float] = [0.0, 0.0, 0.0, 0.0]
var wheel_vf: Array[float] = [0.0, 0.0, 0.0, 0.0]
# Kerb rumble intensity 0..1 (smoothed); main.gd maps it to camera shake.
var kerb_level := 0.0

# dynamic (relaxation-length) slip states per wheel
var _slip_lon_state: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _slip_lat_state: Array[float] = [0.0, 0.0, 0.0, 0.0]
# per-wheel tire wear 0..1 (race-long) and the surface probe stored from
# the suspension raycast (grip / surface name of the ground under the wheel)
var _wear: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _surf_grips: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _surf_names: Array[String] = ["asphalt", "asphalt", "asphalt", "asphalt"]

var _wheel_local_pos: Array[Vector3] = []
var _front_mask: Array[bool] = [true, true, false, false]
var _driven_mask: Array[bool] = [false, false, true, true]
# rate-limited traction-control cut factor (0 = no cut): a static slip
# threshold + gain creates a thrust-slip-pitch limit cycle (~10 Hz hop)
# at full throttle near the grip limit; slewing the cut rate-limits the
# loop energy instead of pumping it
var _tc_cut: float = 0.0
var _tires: Dictionary
var _susp: Dictionary
var _aero: Dictionary
var _assist_params: Dictionary
var _steer_params: Dictionary
var _brakes: Dictionary
var _nitro_cfg: Dictionary
var _engine_cfg: Dictionary
var _kerb_cfg: Dictionary
var _mass := 750.0


func _ready() -> void:
	var text := FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	data = JSON.parse_string(text) as Dictionary
	_tires = data.get("tires", {})
	_susp = data.get("suspension", {})
	_aero = data.get("aero", {})
	_assist_params = data.get("assists", {})
	_steer_params = data.get("steering", {})
	_brakes = data.get("brakes", {})
	_nitro_cfg = data.get("nitro", {})
	_engine_cfg = data.get("engine", {})
	_kerb_cfg = data.get("kerb", {})
	_mass = float(data.get("mass_kg", 750.0))

	powertrain = Powertrain.new(data)
	nitro_left = nitro_capacity()
	assists_on = {
		"auto_gearbox": true,
		"steering_assist": true,
		"stability_control": true,
		"abs": true,
		"traction_control": true,
	}

	var wheelbase := float(data.get("wheelbase_m", 3.1))
	# CG to front axle distance = wheelbase * (1 - front load fraction)
	var half_front := wheelbase * (1.0 - float(data.get("weight_distribution_front", 0.45)))
	var half_rear := wheelbase - half_front
	var track_width := float(data.get("track_width_m", 1.9)) * 0.5
	_wheel_local_pos = [
		Vector3(-track_width, 0.0, -half_front),
		Vector3(track_width, 0.0, -half_front),
		Vector3(-track_width, 0.0, half_rear),
		Vector3(track_width, 0.0, half_rear),
	]

	mass = _mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# origin sits at wheel-attach plane; COM is below it per config
	center_of_mass = Vector3(0.0, -float(data.get("center_of_mass_height_m", 0.30)), 0.0)
	# Godot applies default linear/angular damping (0.1) to rigid bodies:
	# that is a hidden speed-proportional brake. Our aero model owns drag,
	# so damping is zeroed explicitly (see docs/PHYSICS.md).
	linear_damp = 0.0
	angular_damp = 0.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.2  # body contacts, not wheels
	contact_monitor = true
	max_contacts_reported = 4


func _physics_process(_delta: float) -> void:
	sim_time += TICK_DT
	kerb_level = maxf(kerb_level - KERB_DECAY_PER_S * TICK_DT, 0.0)
	var input := _gather_input()
	_update_steering(input)
	_step_wheels(input)
	_apply_aero()
	_apply_nitro(input)
	_apply_assists(input)
	_update_visual_wheels()


# ---------------------------------------------------------------- input


func _gather_input() -> Dictionary:
	var input: Dictionary
	if external_input != null:
		input = external_input
	else:
		input = {
			"throttle": Input.get_action_strength("throttle"),
			"brake": Input.get_action_strength("brake"),
			"steer": Input.get_axis("steer_left", "steer_right"),
			"nitro": Input.is_action_pressed("nitro"),
			"shift_up": Input.is_action_just_pressed("shift_up"),
			"shift_down": Input.is_action_just_pressed("shift_down"),
		}
	last_input = input
	return input


func _update_steering(input: Dictionary) -> void:
	var speed := linear_velocity.length()
	var max_angle := _max_steer_angle(speed)
	if bool(assists_on.get("steering_assist", false)):
		max_angle = lerpf(
			max_angle,
			max_angle * 0.5,
			(
				float(_assist_params.get("steering_assist_speed_gain", 0.35))
				* clampf(speed / 60.0, 0.0, 1.0)
			)
		)
	var target := float(input.get("steer", 0.0)) * max_angle
	var rate := float(_steer_params.get("rate_rad_per_s", 4.5)) * TICK_DT
	steering_angle = move_toward(steering_angle, target, rate)


func _max_steer_angle(speed: float) -> float:
	var max_angle := float(_steer_params.get("max_angle_rad", 0.55))
	var min_angle := float(_steer_params.get("min_angle_at_top_speed_rad", 0.09))
	var top := maxf(float(_steer_params.get("top_speed_for_min_rad", 80.0)), 1.0)
	var t := clampf(speed / top, 0.0, 1.0)
	return lerpf(max_angle, min_angle, t)


# ---------------------------------------------------------------- wheels


func _step_wheels(input: Dictionary) -> void:
	var throttle := float(input.get("throttle", 0.0))
	var brake := float(input.get("brake", 0.0))
	var space := get_world_3d().direct_space_state
	var wheel_radius := float(data.get("wheel", {}).get("radius_m", 0.33))
	var spin_inertia := float(data.get("wheel", {}).get("spin_inertia_kg_m2", 0.9))
	var rest_length := float(_susp.get("rest_length_m", 0.25))
	var spring_rate := float(_susp.get("spring_rate_n_per_m", 120000.0))
	var damper := float(_susp.get("damper_n_s_per_m", 8000.0))
	var arb := float(_susp.get("anti_roll_bar_n_per_m", 18000.0))
	var brake_torque := float(_brakes.get("max_torque_nm", 4000.0)) * brake
	var bias := float(_brakes.get("bias_front", 0.58))

	# average rear wheel speed drives rpm estimate (reverse-aware sign)
	var rear_speed := (wheel_spin[2] + wheel_spin[3]) * 0.5
	powertrain.update_rpm(rear_speed, throttle)
	if bool(assists_on.get("auto_gearbox", false)):
		powertrain.auto_shift(rear_speed, throttle, sim_time)

		# TC as a rate-limited controller: target cut from slip error,
		# slew toward it; no static on/off threshold hunting

	elif bool(input.get("shift_up", false)):
		powertrain.request_shift(1, sim_time)

		# TC as a rate-limited controller: target cut from slip error,
		# slew toward it; no static on/off threshold hunting

	elif bool(input.get("shift_down", false)):
		powertrain.request_shift(-1, sim_time)

		# TC as a rate-limited controller: target cut from slip error,
		# slew toward it; no static on/off threshold hunting

	var drive_torque := powertrain.wheel_torque(sim_time, throttle)
	if bool(assists_on.get("traction_control", false)):
		# TC as a rate-limited controller: target cut from slip error,
		# slew toward it; no static on/off threshold hunting
		var rear_slip := maxf(wheel_slip_ratios[2], wheel_slip_ratios[3])
		var tc_start := float(_assist_params.get("tc_slip_threshold", 0.15))
		var tc_min := float(_assist_params.get("tc_throttle_cut", 0.1))
		var target_cut := 0.0
		if rear_slip > tc_start:
			target_cut = clampf((rear_slip - tc_start) / 0.15, 0.0, 1.0) * (1.0 - tc_min)
		var slew := float(_assist_params.get("tc_slew_per_s", 8.0))
		_tc_cut = move_toward(_tc_cut, target_cut, slew * TICK_DT)
		drive_torque *= 1.0 - _tc_cut

	# engine braking (0.7.0): closed-throttle engine drag on the driven
	# axle; split across both rear wheels in the spin update below
	var engine_brake := engine_brake_nm(
		powertrain.rpm, powertrain.redline_rpm(), throttle, _engine_cfg
	)
	var compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(4):
		compressions[i] = _raycast_compression(i, rest_length, wheel_radius, space)

	for i in range(4):
		var attach_global := to_global(_wheel_local_pos[i])
		var up := global_transform.basis.y
		var compression := compressions[i]
		wheel_contacts[i] = compression > 0.0

		if not wheel_contacts[i]:
			wheel_loads[i] = 0.0
			wheel_spin[i] *= 0.999
			continue

		var compression_rate := _compression_rate(i)
		var spring_force := spring_rate * compression + damper * compression_rate
		spring_force = maxf(spring_force, 0.0)
		var other := i + 1 if i % 2 == 0 else i - 1
		var arb_force := arb * (compressions[i] - compressions[other])
		# ARB force can exceed the spring load on the unloaded wheel: clamp so
		# a stretched wheel never pulls the car down (negative Fz is a tire bug)
		var fz := maxf(spring_force + arb_force, 0.0)
		wheel_loads[i] = fz
		apply_force(up * fz, attach_global - global_transform.origin)
		# kerb rumble (0.7.0): high-frequency vertical excitation under the
		# contact patch; bump fraction feeds the camera shake path
		if _surf_names[i] == "kerb" and fz > 0.0:
			var bump := kerb_bump_force(fz, sim_time, _kerb_cfg)
			apply_force(up * bump, attach_global - global_transform.origin)
			kerb_level = maxf(
				kerb_level, absf(bump) / maxf(fz * float(_kerb_cfg.get("force_frac", 0.12)), 1.0)
			)

		var steer := steering_angle if _front_mask[i] else 0.0
		# positive steer = wheels point RIGHT (input axis convention: D = +1);
		# a +Y rotation turns -Z toward -X (left), hence the minus sign
		var forward := (global_transform.basis.z * -1.0).rotated(global_transform.basis.y, -steer)
		var side := forward.cross(Vector3.UP).normalized()
		var contact := attach_global - up * (rest_length + wheel_radius - compression)
		var contact_velocity := _velocity_at(contact)

		var v_forward := contact_velocity.dot(forward)
		var v_side := contact_velocity.dot(side)

		var relax := float(_tires.get("relaxation_length_m", 0.15))
		var tau := relax / maxf(absf(v_forward), 0.5)
		var alpha := clampf(TICK_DT / maxf(tau, 0.001), 0.02, 1.0)
		var ss_slip_ratio := (wheel_spin[i] * wheel_radius - v_forward) / maxf(absf(v_forward), 1.0)
		var ss_slip_angle := atan2(v_side, maxf(absf(v_forward), 1.0))
		_slip_lon_state[i] = lerpf(_slip_lon_state[i], ss_slip_ratio, alpha)
		# lateral relaxation mirrors the longitudinal one: the raw slip angle
		# snapped the front axle to peak force within one tick (twitchy steering)
		_slip_lat_state[i] = lerpf(_slip_lat_state[i], ss_slip_angle, alpha)
		var slip_ratio := _slip_lon_state[i]
		var slip_angle := _slip_lat_state[i]
		wheel_slip_ratios[i] = slip_ratio
		wheel_slip_angles[i] = slip_angle

		# tire wear (0.7.0): slip energy under load eats grip over a race;
		# the wear factor multiplies the surface friction per wheel
		var surface_mu := _surface_grip(i) * wear_grip_factor(_wear[i], _tires)
		var fx := TireModel.longitudinal_force(fz, slip_ratio, surface_mu, _tires)
		var fy := -TireModel.lateral_force(fz, slip_angle, surface_mu, _tires)
		var combined := TireModel.combine(fx, fy, fz, surface_mu)
		fx = combined.x
		fy = combined.y
		wheel_fx[i] = fx
		wheel_vf[i] = v_forward
		_wear[i] = wear_step(_wear[i], fz, slip_ratio, slip_angle, TICK_DT, _tires)

		var axle_bias := bias if _front_mask[i] else 1.0 - bias
		var this_brake := brake_torque * axle_bias * 0.5
		if bool(assists_on.get("abs", false)) and slip_ratio < 0.0:
			var abs_start := float(_assist_params.get("abs_slip_threshold", -0.25))
			if slip_ratio < abs_start:
				this_brake *= lerpf(
					1.0,
					float(_assist_params.get("abs_brake_scale", 0.15)),
					clampf((-slip_ratio + abs_start) / 0.25, 0.0, 1.0)
				)
		var net_torque := drive_torque * (1.0 if _driven_mask[i] else 0.0) - fx * wheel_radius
		if _driven_mask[i]:
			net_torque -= signf(wheel_spin[i]) * engine_brake * 0.5
		net_torque -= signf(wheel_spin[i]) * this_brake
		net_torque -= float(_tires.get("spin_damp_nms", 1.2)) * wheel_spin[i]
		wheel_spin[i] += net_torque / spin_inertia * TICK_DT
		if (
			brake > 0.0
			and drive_torque == 0.0
			and absf(wheel_spin[i]) < this_brake / spin_inertia * TICK_DT
		):
			wheel_spin[i] = 0.0
		apply_force(forward * fx + side * fy, contact - global_transform.origin)
		# rolling resistance (0.7.0): small load-proportional road drag that
		# makes the car coast down instead of rolling forever
		var rr_coeff := float(_tires.get("rolling_resistance_coeff", 0.013))
		apply_force(
			forward * rolling_resistance(fz, v_forward, rr_coeff), contact - global_transform.origin
		)


func _raycast_compression(
	i: int, rest_length: float, wheel_radius: float, space: PhysicsDirectSpaceState3D
) -> float:
	var attach_global := to_global(_wheel_local_pos[i])
	var up := global_transform.basis.y
	var from := attach_global
	var to := attach_global - up * (rest_length + wheel_radius)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_surf_grips[i] = 1.0
		_surf_names[i] = "asphalt"
		return 0.0
	# surface probe rides the SAME ray as the suspension probe: the extra
	# 4 rays/tick of the Phase-1 _surface_grip raycast are gone
	var node := hit.get("collider") as Node
	if node != null and node.has_meta("grip"):
		_surf_grips[i] = float(node.get_meta("grip"))
		_surf_names[i] = (str(node.get_meta("surface")) if node.has_meta("surface") else "asphalt")
	else:
		_surf_grips[i] = 1.0
		_surf_names[i] = "asphalt"
	var distance := from.distance_to(hit["position"] as Vector3)
	var compression := rest_length + wheel_radius - distance
	return clampf(compression, 0.0, float(_susp.get("max_compression_m", 0.14)))


func _compression_rate(_i: int) -> float:
	# Phase 1 simplification: derive damper velocity from body angular/linear
	# velocity at attach point projected on up axis
	var attach_global := to_global(_wheel_local_pos[_i])
	var velocity_at := _velocity_at(attach_global)
	return -velocity_at.dot(global_transform.basis.y)


func _velocity_at(global_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(global_point - global_transform.origin)


func _surface_grip(i: int) -> float:
	return _surf_grips[i]


# -------------------------------------------------- surface/wear helpers


## Pure kerb rumble force [N]: a vertical sinusoid under the contact patch.
## fz: wheel load [N], sim_time: physics clock [s], cfg: vehicle.json "kerb".
static func kerb_bump_force(fz: float, sim_time: float, cfg: Dictionary) -> float:
	if fz <= 0.0:
		return 0.0
	var frac := float(cfg.get("force_frac", 0.12))
	var hz := maxf(float(cfg.get("vibration_hz", 18.0)), 0.1)
	return fz * frac * sin(sim_time * TAU * hz)


## Pure engine-brake torque [Nm] at the crank: closed-throttle drag scaled by
## the rpm share of the redline. Zero with any real throttle input.
static func engine_brake_nm(rpm: float, redline: float, throttle: float, cfg: Dictionary) -> float:
	if throttle > 0.02 or redline <= 0.0:
		return 0.0
	var max_nm := float(cfg.get("brake_nm", 60.0))
	return maxf(rpm, 0.0) / redline * max_nm


## Pure rolling-resistance force [N]: opposes the direction of travel.
static func rolling_resistance(fz: float, v_forward: float, coeff: float) -> float:
	if fz <= 0.0:
		return 0.0
	return -signf(v_forward) * coeff * fz


## Pure tire-wear step [0..1]: load + slip energy accumulate damage.
## wear_rate_per_s calibrates the pace; wear_slip_weight makes sliding
## tires (lockups, big slides) wear much faster than loaded rolling ones.
static func wear_step(
	wear: float, fz: float, slip_ratio: float, slip_angle: float, delta: float, tires: Dictionary
) -> float:
	var rate := float(tires.get("wear_rate_per_s", 0.00035))
	var slip_weight := float(tires.get("wear_slip_weight", 5.0))
	var nominal := maxf(float(tires.get("nominal_load_n", 2000.0)), 1.0)
	var load := clampf(fz / nominal, 0.0, 3.0)
	var slip_mag := absf(slip_ratio) + absf(slip_angle)
	var next_wear := wear + delta * rate * load * (0.5 + slip_mag * slip_weight)
	return clampf(next_wear, 0.0, 1.0)


## Grip multiplier from wear: fresh tires 1.0, fully worn tires lose up to
## tires.wear_grip_loss_max of friction (arcade-friendly cap).
static func wear_grip_factor(wear: float, tires: Dictionary) -> float:
	return 1.0 - clampf(wear, 0.0, 1.0) * float(tires.get("wear_grip_loss_max", 0.10))


# ---------------------------------------------------------------- nitro


## Full tank in seconds of boost (from vehicle.json "nitro").
func nitro_capacity() -> float:
	return float(_nitro_cfg.get("capacity_s", 3.0))


## Tank charge fraction 0..1 (HUD gauge / nitro pitch read it).
func nitro_frac() -> float:
	return clampf(nitro_left / maxf(nitro_capacity(), 0.001), 0.0, 1.0)


## Mean tire wear 0..1 across the four wheels (HUD / trace read it).
func tire_wear_avg() -> float:
	var total := 0.0
	for w in _wear:
		total += w
	return total / maxf(_wear.size(), 1)


## Pure tank step (unit-testable): drain while boosting, refill while idle.
static func nitro_tank_step(left: float, active: bool, delta: float, cfg: Dictionary) -> float:
	var capacity := float(cfg.get("capacity_s", 3.0))
	if capacity <= 0.0:
		return 0.0
	if active:
		return maxf(left - delta, 0.0)
	return minf(left + float(cfg.get("regen_per_s", 0.4)) * delta, capacity)


## Boost thrust while nitro is held and the tank has charge. AI cars never
## request nitro, so this is a pure player tool (and the RaceAudio nitro
## loop keys off nitro_active).
func _apply_nitro(input: Dictionary) -> void:
	var capacity := nitro_capacity()
	if capacity <= 0.0:
		nitro_active = false
		return
	var speed := linear_velocity.length()
	var pressed := bool(input.get("nitro", false))
	nitro_active = (
		pressed and nitro_left > 0.0 and speed >= float(_nitro_cfg.get("min_speed_mps", 2.0))
	)
	nitro_left = nitro_tank_step(nitro_left, nitro_active, TICK_DT, _nitro_cfg)
	if nitro_active:
		apply_central_force(-global_transform.basis.z * float(_nitro_cfg.get("thrust_n", 3600.0)))


# ---------------------------------------------------------------- aero


func _apply_aero() -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	if speed < 0.1:
		return

	var wake: Dictionary = _aero.get("wake", {})
	var drs: Dictionary = _aero.get("drs", {})
	# slipstream (long-range wake) cuts drag; an open DRS flap adds to it
	var drag_mult := 1.0 - clampf(aero_wake_drag, 0.0, 1.0) * float(wake.get("drag_cut_max", 0.45))
	if drs_active:
		drag_mult *= 1.0 - float(drs.get("drag_cut", 0.28))

	var drag_force := float(_aero.get("drag_coeff", 0.48)) * drag_mult * speed * speed
	apply_central_force(-velocity.normalized() * drag_force)
	# wing balance: per-axle downforce applied at the wheel attach points.
	# Dirty air hits the front wing first (front loss >= rear -> understeer,
	# which is stability-friendly); an open DRS flap sheds rear downforce.
	var dirty_front := clampf(aero_wake_df, 0.0, 1.0) * float(wake.get("downforce_loss_max", 0.3))
	var dirty_rear := dirty_front * float(wake.get("dirty_rear_factor", 0.7))
	var front_cf := float(_aero.get("front_wing_coeff", 0.45)) * (1.0 - dirty_front)
	var rear_cf := float(_aero.get("rear_wing_coeff", 0.55)) * (1.0 - dirty_rear)
	if drs_active:
		front_cf *= 1.0 - float(drs.get("front_df_cut", 0.0))
		rear_cf *= 1.0 - float(drs.get("rear_df_cut", 0.24))

	var q := speed * speed
	# local axle offsets from the body origin (wheel attach plane)
	var front_offset := (
		Vector3(0.0, 0.0, _wheel_local_pos[0].z)
		if _wheel_local_pos.size() == 4
		else Vector3(0.0, 0.0, -1.4)
	)
	var rear_offset := (
		Vector3(0.0, 0.0, _wheel_local_pos[2].z)
		if _wheel_local_pos.size() == 4
		else Vector3(0.0, 0.0, 1.7)
	)
	apply_force(-Vector3.UP * front_cf * q, front_offset)
	apply_force(-Vector3.UP * rear_cf * q, rear_offset)


func _apply_assists(_input: Dictionary) -> void:
	if bool(assists_on.get("stability_control", false)):
		# yaw damping: oppose yaw rate that is not commanded by steering
		var yaw_rate := angular_velocity.y
		apply_torque(
			(
				Vector3.UP
				* -yaw_rate
				* float(_assist_params.get("stability_yaw_gain", 2.5))
				* _mass
				* 0.01
			)
		)


# ---------------------------------------------------------------- visual


func _update_visual_wheels() -> void:
	var container := get_node_or_null("Visuals")
	if container == null:
		return
	var rest_length := float(_susp.get("rest_length_m", 0.25))
	for i in range(4):
		var holder := container.get_node_or_null("WheelHolder%d" % i) as Node3D
		if holder == null:
			continue
		var compression := clampf(
			rest_length + _wheel_radius() - _wheel_ray_distance(i), 0.0, rest_length
		)
		holder.position = _wheel_local_pos[i] - Vector3(0, rest_length - compression, 0)
		if _front_mask[i]:
			holder.rotation.y = -steering_angle
		var axle := holder.get_node_or_null("Axle") as Node3D
		if axle != null:
			axle.rotation.x = wrapf(axle.rotation.x - wheel_spin[i] * TICK_DT, -PI, PI)


func _wheel_radius() -> float:
	return float(data.get("wheel", {}).get("radius_m", 0.33))


func _wheel_ray_distance(i: int) -> float:
	var attach_global := to_global(_wheel_local_pos[i])
	var up := global_transform.basis.y
	var rest_length := float(_susp.get("rest_length_m", 0.25))
	var from := attach_global
	var to := attach_global - up * (rest_length + _wheel_radius())
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return rest_length + _wheel_radius()
	return from.distance_to(hit["position"] as Vector3)


## Reset car to a transform and zero all state (R key / out of track).
func reset_to(transform: Transform3D) -> void:
	global_transform = transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering_angle = 0.0
	sim_time = 0.0
	powertrain.reset()
	nitro_left = nitro_capacity()
	nitro_active = false
	for i in range(4):
		wheel_spin[i] = 0.0
		_slip_lon_state[i] = 0.0
		_slip_lat_state[i] = 0.0
	kerb_level = 0.0
