class_name RaceAudio
extends Node
## Race sound stage (0.5.0): six RPM-banded engine loops crossfaded by
## powertrain rpm, a tire-squeal loop driven by wheel slip, a thruster loop
## while nitro boosts and metal crash one-shots on chassis contact.
## Non-positional players: the arcade camera always follows the player car.
## PROCESS_MODE_ALWAYS keeps the engine purring under the pause menu
## (state updates are skipped while paused).

const ENGINE_BANDS := 6
const BAND_WIDTH := 0.24  # rpm-normalized half-width of a band window
const ENGINE_DB := -7.0
const SKID_DB := -6.0
const NITRO_DB := -6.0
const SILENT_DB := -60.0

var _car: Car
var _engine_players: Array[AudioStreamPlayer] = []
var _skid_player: AudioStreamPlayer
var _nitro_player: AudioStreamPlayer
var _skid_level := 0.0
var _nitro_level := 0.0
var _crash_cooldown := 0.0


func _init(car: Car) -> void:
	_car = car


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(ENGINE_BANDS):
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/engine/engine_%d.wav" % i)
		p.volume_db = SILENT_DB
		add_child(p)
		_engine_players.append(p)
	_skid_player = AudioStreamPlayer.new()
	_skid_player.stream = load("res://assets/audio/tires/skid_loop.wav")
	_skid_player.volume_db = SILENT_DB
	add_child(_skid_player)
	_nitro_player = AudioStreamPlayer.new()
	_nitro_player.stream = load("res://assets/audio/nitro/nitro_loop.wav")
	_nitro_player.volume_db = SILENT_DB
	add_child(_nitro_player)
	for p in _engine_players:
		p.play()
	_skid_player.play()
	_nitro_player.play()
	if _car != null and not _car.body_entered.is_connected(_on_body_entered):
		_car.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _car == null or _car.powertrain == null:
		return
	if get_tree() != null and get_tree().paused:
		return  # hold levels while the pause menu is open
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	_update_engine()
	_update_skid(delta)
	_update_nitro(delta)


# ----------------------------------------------------------- engine


## 0..1 position between idle and redline (clamped).
static func engine_norm_rpm(rpm: float, idle_rpm: float, redline_rpm: float) -> float:
	return clampf((rpm - idle_rpm) / maxf(redline_rpm - idle_rpm, 1.0), 0.0, 1.0)


## Raised-cosine window per band; bands centered at 0, 0.2 .. 1.0.
static func band_weights(rpm_norm: float) -> Array[float]:
	var weights: Array[float] = []
	for i in range(ENGINE_BANDS):
		var center := float(i) / float(ENGINE_BANDS - 1)
		var w := clampf(1.0 - absf(rpm_norm - center) / BAND_WIDTH, 0.0, 1.0)
		weights.append(w)
	return weights


func _update_engine() -> void:
	var rpm_norm := engine_norm_rpm(
		_car.powertrain.rpm, _car.powertrain.idle_rpm(), _car.powertrain.redline_rpm()
	)
	var weights := band_weights(rpm_norm)
	for i in range(ENGINE_BANDS):
		var w: float = weights[i]
		var p := _engine_players[i]
		p.volume_db = lerpf(SILENT_DB, ENGINE_DB, w * w)
		var center := float(i) / float(ENGINE_BANDS - 1)
		p.pitch_scale = clampf(0.92 + (rpm_norm - center) * 0.30, 0.8, 1.25)


# ------------------------------------------------------------- skid


func _update_skid(delta: float) -> void:
	var max_lat := 0.0
	var max_lon := 0.0
	for i in range(4):
		if _car.wheel_contacts[i]:
			max_lat = maxf(max_lat, absf(_car.wheel_slip_angles[i]))
			max_lon = maxf(max_lon, absf(_car.wheel_slip_ratios[i]))
	var speed := _car.linear_velocity.length()
	var target := 0.0
	if speed > 4.0:
		var lateral := clampf((max_lat - 0.16) / 0.20, 0.0, 1.0)
		var longitudinal := clampf((max_lon - 0.25) / 0.30, 0.0, 1.0) * 0.8
		target = maxf(lateral, longitudinal)
	_skid_level = lerpf(_skid_level, target, minf(delta * 12.0, 1.0))
	_skid_player.volume_db = lerpf(SILENT_DB, SKID_DB, _skid_level)
	_skid_player.pitch_scale = lerpf(0.85, 1.18, _skid_level)


# ------------------------------------------------------------ nitro


func _update_nitro(delta: float) -> void:
	var target := 1.0 if _car.nitro_active else 0.0
	_nitro_level = lerpf(_nitro_level, target, minf(delta * 10.0, 1.0))
	_nitro_player.volume_db = lerpf(SILENT_DB, NITRO_DB, _nitro_level)
	_nitro_player.pitch_scale = 1.0 + 0.08 * (1.0 - _car.nitro_frac())


# ------------------------------------------------------------ crash


func _on_body_entered(_body: Node) -> void:
	if _crash_cooldown > 0.0:
		return
	var speed := _car.linear_velocity.length()
	if speed < 5.0:
		return
	_crash_cooldown = 0.4
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.call("crash", clampf(speed / 30.0, 0.2, 1.0))
