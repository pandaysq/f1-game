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

## Set by tests / replay code to drive the car deterministically.
## Dictionary with keys: throttle, brake, steer [-1..1], nitro, shift_up,
## shift_down. When non-null, real input is ignored.
var external_input: Variant = null

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

# dynamic (relaxation-length) slip states per wheel
var _slip_lon_state: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _slip_lat_state: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _wheel_local_pos: Array[Vector3] = []
var _front_mask: Array[bool] = [true, true, false, false]
var _driven_mask: Array[bool] = [false, false, true, true]
var _tires: Dictionary
var _susp: Dictionary
var _aero: Dictionary
var _assist_params: Dictionary
var _steer_params: Dictionary
var _brakes: Dictionary
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
	_mass = float(data.get("mass_kg", 750.0))

	powertrain = Powertrain.new(data)
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
	var input := _gather_input()
	_update_steering(input)
	_step_wheels(input)
	_apply_aero()
	_apply_assists(input)
	_update_visual_wheels()


# ---------------------------------------------------------------- input


func _gather_input() -> Dictionary:
	if external_input != null:
		return external_input
	return {
		"throttle": Input.get_action_strength("throttle"),
		"brake": Input.get_action_strength("brake"),
		"steer": Input.get_axis("steer_left", "steer_right"),
		"nitro": Input.is_action_pressed("nitro"),
		"shift_up": Input.is_action_just_pressed("shift_up"),
		"shift_down": Input.is_action_just_pressed("shift_down"),
	}


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

		# smooth TC: taper drive torque as rear slip passes the grip peak
		# (peak longitudinal force is near slip ratio ~0.14 with lon_B/lon_C)

		# suspension compression per wheel (needed by ARB before per-wheel forces)

		# free wheel spin decays slowly (air drag on wheel)

		# suspension + ARB [N]

		# tire coordinate frame: forward = rolling direction of this wheel

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified

		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)

		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative

		# brake torque [Nm], front/rear split; ABS reduces locking wheels

		# wheel spin dynamics: I * dw = drive - Fx*r - brake

		# bearing / drivetrain drag: kills numerical limit cycles

		# brake cannot reverse wheel rotation direction within one tick
	elif bool(input.get("shift_up", false)):
		powertrain.request_shift(1, sim_time)

		# smooth TC: taper drive torque as rear slip passes the grip peak
		# (peak longitudinal force is near slip ratio ~0.14 with lon_B/lon_C)

		# suspension compression per wheel (needed by ARB before per-wheel forces)

		# free wheel spin decays slowly (air drag on wheel)

		# suspension + ARB [N]

		# tire coordinate frame: forward = rolling direction of this wheel

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified

		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)

		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative

		# brake torque [Nm], front/rear split; ABS reduces locking wheels

		# wheel spin dynamics: I * dw = drive - Fx*r - brake

		# bearing / drivetrain drag: kills numerical limit cycles

		# brake cannot reverse wheel rotation direction within one tick
	elif bool(input.get("shift_down", false)):
		powertrain.request_shift(-1, sim_time)

		# smooth TC: taper drive torque as rear slip passes the grip peak
		# (peak longitudinal force is near slip ratio ~0.14 with lon_B/lon_C)

		# suspension compression per wheel (needed by ARB before per-wheel forces)

		# free wheel spin decays slowly (air drag on wheel)

		# suspension + ARB [N]

		# tire coordinate frame: forward = rolling direction of this wheel

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified

		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)

		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative

		# brake torque [Nm], front/rear split; ABS reduces locking wheels

		# wheel spin dynamics: I * dw = drive - Fx*r - brake

		# bearing / drivetrain drag: kills numerical limit cycles

		# brake cannot reverse wheel rotation direction within one tick
	var drive_torque := powertrain.wheel_torque(sim_time, throttle)
	if bool(assists_on.get("traction_control", false)):
		# smooth TC: taper drive torque as rear slip passes the grip peak
		# (peak longitudinal force is near slip ratio ~0.14 with lon_B/lon_C)
		var rear_slip := maxf(wheel_slip_ratios[2], wheel_slip_ratios[3])
		var tc_start := float(_assist_params.get("tc_slip_threshold", 0.25))
		if rear_slip > tc_start:
			drive_torque *= lerpf(
				1.0,
				float(_assist_params.get("tc_throttle_cut", 0.1)),
				clampf((rear_slip - tc_start) / 0.25, 0.0, 1.0)
			)

		# suspension compression per wheel (needed by ARB before per-wheel forces)

		# free wheel spin decays slowly (air drag on wheel)

		# suspension + ARB [N]

		# tire coordinate frame: forward = rolling direction of this wheel

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified

		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)

		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative

		# brake torque [Nm], front/rear split; ABS reduces locking wheels

		# wheel spin dynamics: I * dw = drive - Fx*r - brake

		# bearing / drivetrain drag: kills numerical limit cycles

		# brake cannot reverse wheel rotation direction within one tick
	var compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in range(4):
		compressions[i] = _raycast_compression(i, rest_length, wheel_radius, space)

		# free wheel spin decays slowly (air drag on wheel)

		# suspension + ARB [N]

		# tire coordinate frame: forward = rolling direction of this wheel

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified

		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)

		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative

		# brake torque [Nm], front/rear split; ABS reduces locking wheels

		# wheel spin dynamics: I * dw = drive - Fx*r - brake

		# bearing / drivetrain drag: kills numerical limit cycles

		# brake cannot reverse wheel rotation direction within one tick
	for i in range(4):
		var attach_global := to_global(_wheel_local_pos[i])
		var up := global_transform.basis.y
		var compression := compressions[i]
		wheel_contacts[i] = compression > 0.0

		if not wheel_contacts[i]:
			wheel_loads[i] = 0.0
			# free wheel spin decays slowly (air drag on wheel)
			wheel_spin[i] *= 0.999
			continue

			# suspension + ARB [N]

			# tire coordinate frame: forward = rolling direction of this wheel

			# dynamic slip with relaxation length (Pacejka MF style): the contact
			# patch needs travel to build force; the lag keeps the wheel spin
			# loop stable at 120 Hz and is physically justified

			# lateral slip stays instantaneous: no internal state loop there, and
			# the lag on slip angle destabilized yaw (energy pump at saturation)

			# lateral force opposes the lateral velocity: slip_angle is measured
			# along the wheel's right axis, so the restoring force is negative

			# brake torque [Nm], front/rear split; ABS reduces locking wheels

			# wheel spin dynamics: I * dw = drive - Fx*r - brake

			# bearing / drivetrain drag: kills numerical limit cycles

			# brake cannot reverse wheel rotation direction within one tick
		var compression_rate := _compression_rate(i)
		var spring_force := spring_rate * compression + damper * compression_rate
		spring_force = maxf(spring_force, 0.0)
		var other := i + 1 if i % 2 == 0 else i - 1
		var arb_force := arb * (compressions[i] - compressions[other])
		var fz := spring_force + arb_force

		wheel_loads[i] = fz
		apply_force(up * fz, attach_global - global_transform.origin)

		# tire coordinate frame: forward = rolling direction of this wheel
		var steer := steering_angle if _front_mask[i] else 0.0
		var forward := (global_transform.basis.z * -1.0).rotated(global_transform.basis.y, steer)
		var side := forward.cross(Vector3.UP).normalized()
		var contact := attach_global - up * (rest_length - compression)
		var contact_velocity := _velocity_at(contact)

		var v_forward := contact_velocity.dot(forward)
		var v_side := contact_velocity.dot(side)

		# dynamic slip with relaxation length (Pacejka MF style): the contact
		# patch needs travel to build force; the lag keeps the wheel spin
		# loop stable at 120 Hz and is physically justified
		var relax := float(_tires.get("relaxation_length_m", 0.15))
		var tau := relax / maxf(absf(v_forward), 0.5)
		var alpha := clampf(TICK_DT / maxf(tau, 0.001), 0.02, 1.0)
		var ss_slip_ratio := (wheel_spin[i] * wheel_radius - v_forward) / maxf(absf(v_forward), 1.0)
		var ss_slip_angle := atan2(v_side, maxf(absf(v_forward), 1.0))
		_slip_lon_state[i] = lerpf(_slip_lon_state[i], ss_slip_ratio, alpha)
		# lateral slip stays instantaneous: no internal state loop there, and
		# the lag on slip angle destabilized yaw (energy pump at saturation)
		var slip_ratio := _slip_lon_state[i]
		var slip_angle := ss_slip_angle
		wheel_slip_ratios[i] = slip_ratio
		wheel_slip_angles[i] = slip_angle

		var surface_mu := _surface_grip(contact)
		var fx := TireModel.longitudinal_force(fz, slip_ratio, surface_mu, _tires)
		# lateral force opposes the lateral velocity: slip_angle is measured
		# along the wheel's right axis, so the restoring force is negative
		var fy := -TireModel.lateral_force(fz, slip_angle, surface_mu, _tires)
		var combined := TireModel.combine(fx, fy, fz, surface_mu)
		fx = combined.x
		fy = combined.y
		wheel_fx[i] = fx
		wheel_vf[i] = v_forward

		# brake torque [Nm], front/rear split; ABS reduces locking wheels
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

				# wheel spin dynamics: I * dw = drive - Fx*r - brake

				# bearing / drivetrain drag: kills numerical limit cycles

				# brake cannot reverse wheel rotation direction within one tick
		var net_torque := drive_torque * (1.0 if _driven_mask[i] else 0.0) - fx * wheel_radius
		net_torque -= signf(wheel_spin[i]) * this_brake
		# bearing / drivetrain drag: kills numerical limit cycles
		net_torque -= float(_tires.get("spin_damp_nms", 1.2)) * wheel_spin[i]
		wheel_spin[i] += net_torque / spin_inertia * TICK_DT
		# brake cannot reverse wheel rotation direction within one tick
		if (
			brake > 0.0
			and drive_torque == 0.0
			and absf(wheel_spin[i]) < this_brake / spin_inertia * TICK_DT
		):
			wheel_spin[i] = 0.0
		apply_force(forward * fx + side * fy, contact - global_transform.origin)


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
		return 0.0
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


func _surface_grip(contact: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		contact + Vector3.UP * 0.1, contact - Vector3.UP * 0.1, 1, [get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	var collider: Object = hit.get("collider")
	if collider != null and (collider as Node).has_meta("grip"):
		return float((collider as Node).get_meta("grip"))
	return 1.0


# ---------------------------------------------------------------- aero


func _apply_aero() -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	if speed < 0.1:
		return
	var drag_force := float(_aero.get("drag_coeff", 0.48)) * speed * speed
	apply_central_force(-velocity.normalized() * drag_force)
	var downforce := float(_aero.get("downforce_coeff", 1.0)) * speed * speed
	apply_central_force(-Vector3.UP * downforce)


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

		# wheel center hangs below the attach point by (rest_length - compression)

		# rolling around the axle (local X axis of the cylinder mesh)
	var rest_length := float(_susp.get("rest_length_m", 0.25))
	for i in range(4):
		var holder := container.get_node_or_null("WheelHolder%d" % i) as Node3D
		if holder == null:
			continue

			# wheel center hangs below the attach point by (rest_length - compression)

			# rolling around the axle (local X axis of the cylinder mesh)
		var mesh := holder.get_node_or_null("Mesh") as MeshInstance3D
		if mesh == null:
			continue

			# wheel center hangs below the attach point by (rest_length - compression)

			# rolling around the axle (local X axis of the cylinder mesh)
		var compression := clampf(
			rest_length + _wheel_radius() - _wheel_ray_distance(i), 0.0, rest_length
		)
		# wheel center hangs below the attach point by (rest_length - compression)
		holder.position = _wheel_local_pos[i] - Vector3(0, rest_length - compression, 0)
		if _front_mask[i]:
			holder.rotation.y = steering_angle
			# rolling around the axle (local X axis of the cylinder mesh)
		mesh.rotate_object_local(Vector3(1, 0, 0), wheel_spin[i] * TICK_DT)


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
	for i in range(4):
		wheel_spin[i] = 0.0
		_slip_lon_state[i] = 0.0
		_slip_lat_state[i] = 0.0
