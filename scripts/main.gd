extends Node3D
## Phase 1 main scene: builds Alpha Loop track, spawns the player car,
## runs the Time Trial session and wires camera / HUD / touch controls.

const TICK_DT := 1.0 / 120.0
const TRACK_PATH := "res://tracks/alpha_loop.json"

var car: Car
var track: TrackData
var session: TimeTrial

@onready var debug_overlay: CanvasLayer = $DebugOverlay


func _ready() -> void:
	var text := FileAccess.get_file_as_string(TRACK_PATH)
	track = TrackData.parse(text, TRACK_PATH)
	if track == null:
		push_error("main: cannot parse track %s" % TRACK_PATH)
		return
	var problems := TrackValidator.validate(track)
	if not problems.is_empty():
		push_error("main: track validation failed: %s" % str(problems))

	TrackBuilder.build(track, self)

	car = VehicleFactory.build()
	add_child(car)
	car.global_transform = TrackBuilder.spawn_transform(track)

	session = TimeTrial.new(track)

	var rig := CameraRig.new(car)
	add_child(rig)
	rig.cockpit_camera.current = true

	add_child(Hud.new(car, session))
	add_child(TouchControls.new())

	debug_overlay.visible = true


func _physics_process(_delta: float) -> void:
	if session != null and car != null:
		session.update(car.global_transform.origin, TICK_DT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_reset_car()
	elif event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()


## Reset the car to the nearest centerline point, facing along the track.
func _reset_car() -> void:
	if car == null or track == null:
		return
	var n := track.point_count()
	var best_index := 0
	var best_distance := INF
	for i in range(n):
		var distance := track.points[i].distance_to(car.global_transform.origin)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	var dir := track.direction_at(best_index)
	var basis := Basis(Vector3.RIGHT, Vector3.UP, -dir)
	var origin := track.points[best_index] + Vector3.UP * 0.6
	car.reset_to(Transform3D(basis, origin))
