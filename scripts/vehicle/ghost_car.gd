class_name GhostCar
extends Node3D
## Time-trial ghost (0.6.0): the Sketchfab body re-materialized as a
## translucent hologram that replays the best-lap recording. No collision,
## no sound, no shadow — purely visual pace reference. The recording time
## starts at the first sample; interpolation is linear between samples.

const BODY_MODEL_PATH := "res://assets/models/car/low_poly_f1.glb"
const BODY_MODEL_SCALE := 0.4239
const GHOST_TINT := Color(0.45, 0.85, 1.0)
const TRANSPARENCY := 0.62

var _samples: Array = []  # [[t, x, y, z, yaw], ...]
var _play_time := 0.0
var _cursor := 0
var _playing := false
var _last_transform := Transform3D()


func _init() -> void:
	var packed: PackedScene = load(BODY_MODEL_PATH)
	if packed == null:
		push_warning("ghost_car: body model missing, ghost disabled")
		return
	var body: Node3D = packed.instantiate()
	body.scale = Vector3.ONE * BODY_MODEL_SCALE
	body.rotation.y = PI  # model faces +Z, car forward is -Z
	add_child(body)
	_hologram(body)
	visible = false


## Recolor + fade every mesh; kill shadows so the ghost does not mislead.
func _hologram(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transparency = TRANSPARENCY
			for s in range(mi.mesh.get_surface_count()):
				var mat := StandardMaterial3D.new()
				mat.albedo_color = GHOST_TINT
				mat.emission_enabled = true
				mat.emission = GHOST_TINT * 0.35
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.roughness = 0.2
				mi.set_surface_override_material(s, mat)
		for c in n.get_children():
			stack.append(c)


## Starts (or restarts) the replay; empty samples hide the ghost.
func play_recording(samples: Array) -> void:
	if samples.size() < 2:
		visible = false
		_playing = false
		return
	_samples = samples
	_play_time = 0.0
	_cursor = 0
	_playing = true
	visible = true


func stop() -> void:
	_playing = false
	visible = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_play_time += delta
	if not _sample_at(_play_time):
		stop()  # recording over: ghost parks until the next best lap
		return
	global_transform = _last_transform


## Linear position + shortest-arc angle interpolation between samples.
## Fills _last_transform; returns false past the end of the recording.
func _sample_at(time: float) -> bool:
	var samples := _samples
	var n := samples.size()
	if n < 2:
		return false
	while _cursor < n - 2 and float(samples[_cursor + 1][0]) <= time:
		_cursor += 1
	var a: Array = samples[_cursor]
	var b: Array = samples[_cursor + 1]
	var span := float(b[0]) - float(a[0])
	var t := 0.0 if span <= 0.0 else clampf((time - float(a[0])) / span, 0.0, 1.0)
	if time >= float(b[0]) and _cursor >= n - 2:
		return false
	var pos := Vector3(
		lerpf(float(a[1]), float(b[1]), t),
		lerpf(float(a[2]), float(b[2]), t),
		lerpf(float(a[3]), float(b[3]), t)
	)
	var yaw := lerp_angle(float(a[4]), float(b[4]), t)
	_last_transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 0.45)
	return true
