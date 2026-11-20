class_name VehicleFactory
extends RefCounted
## Builds the playable car node with procedural low-poly visuals.
## Keeps scenes tiny: everything is code-built from vehicle.json.

const RED_LIVERY := Color(0.88, 0.09, 0.09)
const DARK_LIVERY := Color(0.10, 0.10, 0.12)
const TIRE_COLOR := Color(0.08, 0.08, 0.08)


## Creates a Car (RigidBody3D) with collision shape and visual meshes.
static func build() -> Car:
	var car := Car.new()
	car.name = "PlayerCar"
	car.collision_layer = 2
	car.collision_mask = 1

	_build_collision(car)
	_build_visuals(car)
	return car


static func _build_collision(car: Car) -> void:
	var text := FileAccess.get_file_as_string("res://assets/data/vehicle.json")
	var data := JSON.parse_string(text) as Dictionary
	var box: Dictionary = data.get("collision_box_m", {})
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		float(box.get("width", 1.4)), float(box.get("height", 0.55)), float(box.get("length", 4.3))
	)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	# box centered at CG height below origin (origin = wheel attach plane)
	# box bottom stays ~6 cm above the road at rest (origin = wheel attach plane)
	collision.position = Vector3(
		0.0, -(float(data.get("center_of_mass_height_m", 0.30)) - 0.05), 0.0
	)
	car.add_child(collision)


static func _build_visuals(car: Car) -> void:
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	car.add_child(visuals)

	var data := (
		JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle.json"))
		as Dictionary
	)
	var wheelbase := float(data.get("wheelbase_m", 3.1))
	var half_front := wheelbase * (1.0 - float(data.get("weight_distribution_front", 0.45)))
	var half_rear := wheelbase - half_front
	var track_width := float(data.get("track_width_m", 1.9)) * 0.5
	var cg := float(data.get("center_of_mass_height_m", 0.30))

	# tub + nose + sidepods + wings, all boxes, cockpit view friendly
	_add_box(visuals, "Tub", Vector3(0.75, 0.45, 1.6), Vector3(0, -cg + 0.28, -0.4), DARK_LIVERY)
	_add_box(visuals, "Nose", Vector3(0.4, 0.22, 1.9), Vector3(0, -cg + 0.18, -2.0), RED_LIVERY)
	_add_box(
		visuals,
		"SidepodLeft",
		Vector3(0.35, 0.3, 1.4),
		Vector3(-0.62, -cg + 0.22, 0.15),
		RED_LIVERY
	)
	_add_box(
		visuals,
		"SidepodRight",
		Vector3(0.35, 0.3, 1.4),
		Vector3(0.62, -cg + 0.22, 0.15),
		RED_LIVERY
	)
	_add_box(
		visuals, "EngineCover", Vector3(0.42, 0.35, 1.3), Vector3(0, -cg + 0.42, 0.55), DARK_LIVERY
	)
	_add_box(
		visuals, "FrontWing", Vector3(1.7, 0.06, 0.5), Vector3(0, -cg + 0.05, -2.15), DARK_LIVERY
	)
	_add_box(
		visuals, "RearWing", Vector3(1.5, 0.05, 0.45), Vector3(0, -cg + 0.65, 1.9), DARK_LIVERY
	)
	_add_box(
		visuals, "RearWingPylon", Vector3(0.08, 0.35, 0.3), Vector3(0, -cg + 0.45, 1.9), RED_LIVERY
	)

	# wheels: FL FR RL RR
	var positions := [
		Vector3(-track_width, 0, -half_front),
		Vector3(track_width, 0, -half_front),
		Vector3(-track_width, 0, half_rear),
		Vector3(track_width, 0, half_rear),
	]
	var wheel_radius := float(data.get("wheel", {}).get("radius_m", 0.33))
	var wheel_width := float(data.get("wheel", {}).get("width_m", 0.35))
	for i in range(4):
		# holder: suspension travel (position) + steering (yaw); mesh rolls on X
		var holder := Node3D.new()
		holder.name = "WheelHolder%d" % i
		holder.position = positions[i]
		visuals.add_child(holder)

		var wheel := MeshInstance3D.new()
		wheel.name = "Mesh"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = wheel_radius
		cylinder.bottom_radius = wheel_radius
		cylinder.height = wheel_width
		cylinder.radial_segments = 16
		wheel.mesh = cylinder
		# cylinder axis is Y; rotate so it rolls around X (axle)
		wheel.rotation.z = PI * 0.5
		var wheel_mat := StandardMaterial3D.new()
		wheel_mat.albedo_color = TIRE_COLOR
		wheel_mat.roughness = 0.95
		wheel.material_override = wheel_mat
		holder.add_child(wheel)

		# rim so wheel rotation is visible
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		var rim_mesh := CylinderMesh.new()
		rim_mesh.top_radius = wheel_radius * 0.55
		rim_mesh.bottom_radius = rim_mesh.top_radius
		rim_mesh.height = wheel_width + 0.02
		rim_mesh.radial_segments = 8
		rim.mesh = rim_mesh
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.75, 0.75, 0.8)
		rim_mat.metallic = 0.6
		rim_mat.roughness = 0.35
		rim.material_override = rim_mat
		rim.rotation.z = PI * 0.5
		holder.add_child(rim)


static func _add_box(
	parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color
) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
