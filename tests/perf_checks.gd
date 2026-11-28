class_name PerfChecks
extends RefCounted
## 0.10.2 fps-triage guards: quality preset budgets, merged car body draw
## calls, livery tint through the merge.


static func run(check) -> void:
	_quality_preset_checks(check)
	_merged_body_checks(check)


static func _quality_preset_checks(check) -> void:
	var settings = load("res://scripts/settings.gd").new()
	settings.quality = "low"
	settings.apply_quality()
	var vp: Viewport = Engine.get_main_loop().root
	check.call(
		vp.msaa_3d == Viewport.MSAA_DISABLED and absf(vp.scaling_3d_scale - 0.70) < 0.001,
		"quality low = MSAA off + 0.70 scale"
	)
	settings.quality = "medium"
	settings.apply_quality()
	check.call(
		vp.msaa_3d == Viewport.MSAA_DISABLED and absf(vp.scaling_3d_scale - 0.85) < 0.001,
		"quality medium = MSAA off + 0.85 scale"
	)
	settings.quality = "high"
	settings.apply_quality()
	check.call(
		vp.msaa_3d == Viewport.MSAA_2X and absf(vp.scaling_3d_scale - 1.0) < 0.001,
		"quality high = MSAA 2x + 1.0 scale"
	)
	check.call(absf(settings.shadow_max_distance() - 100.0) < 0.001, "shadow budget high = 100 m")


static func _merged_body_checks(check) -> void:
	var red: Car = VehicleFactory.build(Color(0.88, 0.09, 0.09), "PerfRed")
	var blue: Car = VehicleFactory.build(Color(0.12, 0.45, 0.95), "PerfBlue")
	var red_body := _body_mesh(red)
	var blue_body := _body_mesh(blue)
	check.call(red_body != null, "merged body node exists")
	if red_body == null:
		return
	check.call(blue_body != null, "second car merged body exists")
	# one mesh node instead of ~24 source meshes; surfaces grouped by material
	check.call(red_body.mesh.get_surface_count() <= 24, "merged body surfaces <= 24")
	check.call(_mesh_instance_count(red) <= 12, "car draw nodes <= 12 (was 32)")
	# same-livery cars share the cached ArrayMesh, different liveries do not
	var red2: Car = VehicleFactory.build(Color(0.88, 0.09, 0.09), "PerfRed2")
	check.call(_body_mesh(red2).mesh == red_body.mesh, "same livery shares merged mesh")
	check.call(blue_body.mesh != red_body.mesh, "different livery gets own mesh")
	# the livery tint survives the merge (albedo red vs blue on some surface)
	check.call(_has_albedo(red_body.mesh, Color(0.88, 0.09, 0.09)), "red tint present")
	check.call(_has_albedo(blue_body.mesh, Color(0.12, 0.45, 0.95)), "blue tint present")


static func _body_mesh(car: Car) -> MeshInstance3D:
	var stack: Array[Node] = [car]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name) == "Body":
			return n as MeshInstance3D
		for child in n.get_children():
			stack.append(child)
	return null


static func _mesh_instance_count(car: Car) -> int:
	var count := 0
	var stack: Array[Node] = [car]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			count += 1
		for child in n.get_children():
			stack.append(child)
	return count


static func _has_albedo(mesh: Mesh, color: Color) -> bool:
	for s in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(s)
		if (
			mat is StandardMaterial3D
			and (mat as StandardMaterial3D).albedo_color.is_equal_approx(color)
		):
			return true
	return false
