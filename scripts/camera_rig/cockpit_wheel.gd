class_name CockpitWheel
extends Node3D
## Procedural steering wheel + rpm LED strip (0.6.0), mounted in front of the
## driver eye and only visible in the cockpit camera. The rim spins with the
## steering input (up to ~2.2x the front-wheel angle, like a real rack);
## the 15-LED strip fills green -> yellow -> red with rpm like the F1 wheel.
## Tuning hook: APEX_WHEEL_OVERRIDE="x,y,z" moves the whole assembly.

const RIM_RADIUS := 0.16
const RIM_TUBE := 0.022
const LED_COUNT := 15
## LED arc: from -60 deg to +60 deg around the rim top.
const LED_SPAN_RAD := deg_to_rad(120.0)
const VISUAL_GEAR_RATIO := 2.2

var _rim_root: Node3D
var _led_meshes: Array[MeshInstance3D] = []
var _led_unlit: StandardMaterial3D
var _led_green: StandardMaterial3D
var _led_yellow: StandardMaterial3D
var _led_red: StandardMaterial3D


func _init() -> void:
	var base := Vector3(0.0, 0.44, -0.36)
	var override := OS.get_environment("APEX_WHEEL_OVERRIDE")
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 3:
			base = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	position = base
	# recline: rim top leans toward the car nose, like a real wheel column
	rotation.x = deg_to_rad(-18.0)

	_build_materials()
	_build_rim()
	_build_spokes()
	_build_leds()


func _build_materials() -> void:
	_led_unlit = _led_material(Color(0.09, 0.09, 0.1), Color(0, 0, 0))
	_led_green = _led_material(Color(0.1, 0.85, 0.2), Color(0.1, 0.9, 0.15))
	_led_yellow = _led_material(Color(0.95, 0.8, 0.1), Color(0.9, 0.75, 0.05))
	_led_red = _led_material(Color(0.95, 0.1, 0.05), Color(0.9, 0.05, 0.02))


func _led_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 1.6
	return mat


func _carbon() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.07, 0.085)
	mat.metallic = 0.35
	mat.roughness = 0.55
	return mat


func _build_rim() -> void:
	_rim_root = Node3D.new()
	_rim_root.name = "RimRoot"
	add_child(_rim_root)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = RIM_RADIUS - RIM_TUBE
	torus.outer_radius = RIM_RADIUS + RIM_TUBE
	torus.rings = 24
	torus.ring_segments = 10
	rim.mesh = torus
	rim.material_override = _carbon()
	_rim_root.add_child(rim)
	# top marker stripe: shows the rim angle to the driver
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.012, 0.03)
	marker.mesh = box
	marker.position = Vector3(0.0, RIM_RADIUS, 0.0)
	var red := StandardMaterial3D.new()
	red.albedo_color = F1Theme.RED
	red.roughness = 0.4
	marker.material_override = red
	_rim_root.add_child(marker)


func _build_spokes() -> void:
	for i in range(3):
		var spoke := MeshInstance3D.new()
		spoke.name = "Spoke%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(RIM_RADIUS * 2.0 - 0.05, 0.024, 0.014)
		spoke.mesh = box
		spoke.rotation.z = deg_to_rad(60.0 * float(i))
		spoke.material_override = _carbon()
		_rim_root.add_child(spoke)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 0.035
	cyl.radial_segments = 12
	hub.mesh = cyl
	hub.rotation.x = PI * 0.5  # cylinder axis Y -> wheel axis Z
	hub.material_override = _carbon()
	_rim_root.add_child(hub)


func _build_leds() -> void:
	for i in range(LED_COUNT):
		var led := MeshInstance3D.new()
		led.name = "Led%d" % i
		var sphere := SphereMesh.new()
		sphere.radius = 0.0075
		sphere.height = 0.015
		sphere.radial_segments = 6
		sphere.rings = 4
		led.mesh = sphere
		led.material_override = _led_unlit
		var t := -0.5 + float(i) / float(LED_COUNT - 1)
		var ang := LED_SPAN_RAD * t  # -60..+60 deg, 0 = rim top
		led.position = Vector3(sin(ang) * RIM_RADIUS, cos(ang) * RIM_RADIUS, 0.0)
		_rim_root.add_child(led)
		_led_meshes.append(led)


## Called every physics tick while the cockpit camera is active.
## steer_norm: -1..1; rpm_norm: 0..1 between idle and redline.
func update_state(steer_norm: float, rpm_norm: float) -> void:
	_rim_root.rotation.z = clampf(steer_norm, -1.0, 1.0) * 0.55 * VISUAL_GEAR_RATIO
	var lit := int(clampf(rpm_norm, 0.0, 1.0) * float(LED_COUNT) + 0.5)
	for i in range(LED_COUNT):
		var mat: StandardMaterial3D = _led_unlit
		if i < lit:
			if i < 5:
				mat = _led_green
			elif i < 10:
				mat = _led_yellow
			else:
				mat = _led_red
		_led_meshes[i].material_override = mat
