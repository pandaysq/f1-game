class_name VehicleFactory
extends RefCounted
## Builds the playable car node. Physics stays procedural (vehicle.json);
## the body visual is the Sketchfab low-poly F1 glb (CC-BY 4.0, ASSETS.md),
## with per-car livery tint and a dynamic AABB calibration so the imported
## model matches our wheelbase no matter how the asset is re-exported.
## Wheels stay procedural cylinders driven by the raycast suspension.

const RED_LIVERY := Color(0.88, 0.09, 0.09)
const DARK_LIVERY := Color(0.10, 0.10, 0.12)
const TIRE_COLOR := Color(0.08, 0.08, 0.08)

const BODY_MODEL_PATH := "res://assets/models/car/low_poly_f1.glb"
## glb wheelbase is 7.313 m (front axle +Z, rear axle -Z); ours is 3.1 m.
const BODY_MODEL_SCALE := 0.4239
## Car origin sits at the wheel-attach plane; the imported body must end up
## with its bottom at the collision-box bottom (10 cm road clearance) and
## its axle midpoint at the physics axle midpoint.
const BODY_BOTTOM_Y := -0.47
## vehicle.json: wheelbase 3.1, front load 0.45 -> axle midpoint z below.
const BODY_MID_Z := -0.155
## glb tire nodes are hidden: procedural wheels own suspension + steering.
const BODY_TIRE_NODES := ["FR_Tire", "FL_Tire", "RR_Tire", "RL_Tire"]


## Creates a Car (RigidBody3D) with collision shape and visual meshes.
## livery: optional override of the red accents (AI field colors).
## Layer 2 = cars, mask 1|2 = track + other cars (phase-2 collisions).
static func build(livery: Color = RED_LIVERY, name: String = "PlayerCar") -> Car:
	var car := Car.new()
	car.name = name
	car.collision_layer = 2
	car.collision_mask = 1 | 2

	_build_collision(car)
	_build_visuals(car, livery)
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
	# box bottom sits ~10 cm above the road at rest: clears the 6 cm kerbs,
	# so a hard kerb strike cannot jam the underfloor into a zero-thickness
	# ribbon and tunnel the car through the road (phase-2 lesson)
	collision.position = Vector3(
		0.0, -(float(data.get("center_of_mass_height_m", 0.30)) - 0.09), 0.0
	)
	car.add_child(collision)


static func _build_visuals(car: Car, livery: Color) -> void:
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	car.add_child(visuals)

	_build_body(visuals, livery)

	# wheels: FL FR RL RR (positions mirror the raycast attachments)
	var data := (
		JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle.json"))
		as Dictionary
	)
	var wheelbase := float(data.get("wheelbase_m", 3.1))
	var half_front := wheelbase * (1.0 - float(data.get("weight_distribution_front", 0.45)))
	var half_rear := wheelbase - half_front
	var track_width := float(data.get("track_width_m", 1.9)) * 0.5
	var positions := [
		Vector3(-track_width, 0, -half_front),
		Vector3(track_width, 0, -half_front),
		Vector3(-track_width, 0, half_rear),
		Vector3(track_width, 0, half_rear),
	]
	for i in range(4):
		_build_wheel(visuals, i, positions[i], data)


## Instantiates the glb body, hides its tire nodes, tints the red accents to
## the requested livery, and calibrates scale/offset against the physics.
static func _build_body(visuals: Node3D, livery: Color) -> void:
	var packed: PackedScene = load(BODY_MODEL_PATH)
	if packed == null:
		push_warning("vehicle_factory: body model missing, falling back to boxes")
		_build_box_fallback(visuals, livery)
		return

		# calibrate: measure the local AABB in visuals space, then shift so the
		# body bottom and axle midpoint land on the physics reference points
	var body: Node3D = packed.instantiate()
	body.name = "Body"
	_set_visible_recursive(body, BODY_TIRE_NODES, false)
	body.scale = Vector3.ONE * BODY_MODEL_SCALE
	body.rotation.y = PI  # model faces +Z, car forward is -Z
	visuals.add_child(body)

	_tint_livery(body, livery)

	# calibrate: measure the local AABB in visuals space, then shift so the
	# body bottom and axle midpoint land on the physics reference points
	var aabb := _local_aabb(body)
	var bottom := aabb.position.y
	var mid_z := aabb.get_center().z
	body.position = Vector3(-aabb.get_center().x, BODY_BOTTOM_Y - bottom, BODY_MID_Z - mid_z)


## Livery: duplicate the imported (shared) materials per car and recolor the
## two red accent materials to the team color.
static func _tint_livery(body: Node, livery: Color) -> void:
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat is StandardMaterial3D and _is_red_accent(mat as StandardMaterial3D):
					var tinted := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					tinted.albedo_color = livery
					mi.set_surface_override_material(s, tinted)
		for c in n.get_children():
			stack.append(c)


static func _is_red_accent(mat: StandardMaterial3D) -> bool:
	var lname := mat.resource_name.to_lower()
	if lname.contains("bloody red") or lname.contains("3rdcolor"):
		return true
	var c := mat.albedo_color
	return c.r > 0.5 and c.g < 0.3 and c.b < 0.3


## Hides any Node3D whose name is in the list (recursive).
static func _set_visible_recursive(root: Node, names: Array, visible: bool) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and names.has(String(n.name)):
			(n as Node3D).visible = visible
		for c in n.get_children():
			stack.append(c)


## AABB of all meshes below root, in root's PARENT space (root transform
## included, so scale/rotation set before the call are respected).
static func _local_aabb(root: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	var stack: Array = [[root, root.transform]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D and n != root:
			xf = xf * (n as Node3D).transform
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var box := xf * mi.mesh.get_aabb()
			if first:
				aabb = box
				first = false
			else:
				aabb = aabb.merge(box)
		for c in n.get_children():
			stack.append([c, xf])
	return aabb


static func _build_wheel(visuals: Node3D, index: int, position: Vector3, data: Dictionary) -> void:
	var holder := Node3D.new()
	holder.name = "WheelHolder%d" % index
	holder.position = position
	visuals.add_child(holder)

	var wheel_radius := float(data.get("wheel", {}).get("radius_m", 0.33))
	var wheel_width := float(data.get("wheel", {}).get("width_m", 0.35))
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


## Procedural fallback if the glb is missing (keeps tests green everywhere).
static func _build_box_fallback(visuals: Node3D, livery: Color) -> void:
	var data := (
		JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle.json"))
		as Dictionary
	)
	var cg := float(data.get("center_of_mass_height_m", 0.30))
	_add_box(visuals, "Tub", Vector3(0.75, 0.45, 1.6), Vector3(0, -cg + 0.28, -0.4), DARK_LIVERY)
	_add_box(visuals, "Nose", Vector3(0.4, 0.22, 1.9), Vector3(0, -cg + 0.18, -2.0), livery)
	_add_box(
		visuals, "RearWing", Vector3(1.5, 0.05, 0.45), Vector3(0, -cg + 0.65, 1.9), DARK_LIVERY
	)


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
