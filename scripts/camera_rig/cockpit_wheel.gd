class_name CockpitWheel
extends Node3D
## The mount tilts with the chassis; the wheel and its controls roll as one unit.

const MOUNT_POSITION := Vector3(0.0, 0.45, -0.46)
const MOUNT_PITCH := deg_to_rad(-8.0)
const MAX_ROLL := deg_to_rad(68.0)
const LED_COUNT := 15
const LEDS_PER_COLOR := 5

var _rim_root: Node3D
var _gear_label: Label3D
var _led_meshes: Array[MeshInstance3D] = []
var _led_off: StandardMaterial3D
var _led_colors: Array[StandardMaterial3D] = []
var _last_lit := -1


func _init() -> void:
	position = MOUNT_POSITION
	var override := OS.get_environment("APEX_WHEEL_OVERRIDE")
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 3:
			position = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	rotation.x = MOUNT_PITCH
	_rim_root = Node3D.new()
	_rim_root.name = "RimRoot"
	add_child(_rim_root)
	_build_body()
	_build_display()
	_build_leds()


func _build_body() -> void:
	var shell := _material(Color("303741"), 0.55, 0.28)
	var face := _material(Color("22262d"), 0.73)
	var rubber := _material(Color("373c43"), 0.94)
	var outline := PackedVector2Array([
		Vector2(-0.076, -0.068), Vector2(0.076, -0.068), Vector2(0.118, -0.043),
		Vector2(0.118, 0.048), Vector2(0.088, 0.074), Vector2(-0.088, 0.074),
		Vector2(-0.118, 0.048), Vector2(-0.118, -0.043),
	])
	_add_part(_beveled_mesh(outline, 0.022), Vector3.ZERO, shell)
	var inset := PackedVector2Array()
	for point in outline:
		inset.append(point * 0.92)
	_add_part(_beveled_mesh(inset, 0.009), Vector3(0.0, 0.0, 0.009), face)

	var grip := PackedVector2Array([
		Vector2(-0.017, -0.069), Vector2(0.0, -0.079), Vector2(0.017, -0.069),
		Vector2(0.026, -0.046), Vector2(0.026, 0.046), Vector2(0.017, 0.069),
		Vector2(0.0, 0.079), Vector2(-0.017, 0.069), Vector2(-0.026, 0.046),
		Vector2(-0.026, -0.046),
	])
	var grip_mesh := _beveled_mesh(grip, 0.035)
	var paddles := _material(Color("66727f"), 0.48, 0.45)
	for side in [-1.0, 1.0]:
		_add_part(grip_mesh, Vector3(side * 0.126, -0.003, 0.003), rubber)
		var paddle := _add_box(
			Vector3(0.023, 0.078, 0.007), Vector3(side * 0.115, 0.033, -0.02), paddles
		)
		paddle.rotation.z = side * deg_to_rad(10.0)
		var upper_color := Color("4fb8df") if side < 0.0 else Color("edb950")
		var lower_color := Color("e96156") if side < 0.0 else Color("70bc83")
		_add_dial(Vector3(side * 0.078, 0.025, 0.013), 0.008, _material(upper_color, 0.51))
		_add_dial(Vector3(side * 0.073, -0.019, 0.013), 0.008, _material(lower_color, 0.51))

	_add_dial(Vector3(0.0, -0.050, 0.014), 0.011, _material(Color("be5147"), 0.48))
	_add_box(
		Vector3(0.003, 0.008, 0.001), Vector3(0.0, -0.048, 0.019),
		_material(Color("eee4d9"), 0.6)
	)


func _build_display() -> void:
	_add_box(
		Vector3(0.087, 0.060, 0.009), Vector3(0.0, 0.008, 0.013),
		_material(Color("10181d"), 0.36)
	)
	_gear_label = Label3D.new()
	_gear_label.name = "GearNumber"
	_gear_label.text = "1"
	_gear_label.font_size = 54
	_gear_label.outline_size = 0
	_gear_label.pixel_size = 0.00074
	_gear_label.modulate = Color("d2efeb")
	_gear_label.position = Vector3(0.0, 0.008, 0.019)
	_rim_root.add_child(_gear_label)


func _build_leds() -> void:
	_led_off = _material(Color("3d494e"), 0.44)
	for color in [Color("45ed85"), Color("ffd25c"), Color("ff5f4c")]:
		var mat := _material(color, 0.38)
		mat.emission_enabled = true
		mat.emission = color
		_led_colors.append(mat)
	_add_box(
		Vector3(0.174, 0.017, 0.008), Vector3(0.0, 0.053, 0.013),
		_material(Color("121519"), 0.56)
	)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.008, 0.007, 0.003)
	for i in range(LED_COUNT):
		var x := lerpf(-0.077, 0.077, float(i) / float(LED_COUNT - 1))
		_led_meshes.append(_add_part(cap, Vector3(x, 0.053, 0.018), _led_off))


func _add_dial(pos: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius
	mesh.height = 0.009
	mesh.radial_segments = 12
	mesh.rings = 0
	_add_part(mesh, pos, mat).rotation.x = PI / 2.0


func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_part(mesh, pos, mat)


func _add_part(mesh: Mesh, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	part.material_override = mat
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim_root.add_child(part)
	return part


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


## Extrudes a convex counterclockwise outline in XY, with the driver's face on +Z.
func _beveled_mesh(outline: PackedVector2Array, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var center := Vector2.ZERO
	for point in outline:
		center += point
	center /= outline.size()
	var front := depth * 0.5
	var shoulder := depth * 0.3
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var inner_a := a.lerp(center, 0.16)
		var inner_b := b.lerp(center, 0.16)
		var fa := Vector3(inner_a.x, inner_a.y, front)
		var fb := Vector3(inner_b.x, inner_b.y, front)
		var sa := Vector3(a.x, a.y, shoulder)
		var sb := Vector3(b.x, b.y, shoulder)
		var ba := Vector3(a.x, a.y, -front)
		var bb := Vector3(b.x, b.y, -front)
		_add_triangle(surface, Vector3(center.x, center.y, front), fb, fa)
		_add_triangle(surface, sa, fa, fb)
		_add_triangle(surface, sa, fb, sb)
		_add_triangle(surface, ba, sa, sb)
		_add_triangle(surface, ba, sb, bb)
		_add_triangle(surface, Vector3(center.x, center.y, -front), ba, bb)
	surface.generate_normals()
	return surface.commit()


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func update_state(steer_norm: float, rpm_norm: float, gear: int) -> void:
	# Positive steering rolls clockwise as seen by the driver on +Z.
	_rim_root.rotation.z = -clampf(steer_norm, -1.0, 1.0) * MAX_ROLL
	var gear_text := "R" if gear == 0 else str(gear)
	if _gear_label.text != gear_text:
		_gear_label.text = gear_text
	var lit := roundi(clampf(rpm_norm, 0.0, 1.0) * LED_COUNT)
	if lit == _last_lit:
		return
	_last_lit = lit
	for i in range(LED_COUNT):
		var band := floori(float(i) / LEDS_PER_COLOR)
		_led_meshes[i].material_override = _led_colors[band] if i < lit else _led_off
