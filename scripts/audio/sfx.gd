extends Node
## Global sound effects (0.5.0), autoloaded as "Sfx". A small pool of
## non-positional AudioStreamPlayers for UI + race one-shots; the engine /
## skid / nitro loops live in RaceAudio. PROCESS_MODE_ALWAYS keeps UI sounds
## alive while the tree is paused. Sources: Kenney CC0 packs + OGA loops —
## full attribution table in ASSETS.md.

const SOUNDS := {
	"click": "res://assets/audio/ui/click.ogg",
	"back": "res://assets/audio/ui/back.ogg",
	"open": "res://assets/audio/ui/open.ogg",
	"close": "res://assets/audio/ui/close.ogg",
	"toggle": "res://assets/audio/ui/toggle.ogg",
	"select": "res://assets/audio/ui/select.ogg",
	"beep": "res://assets/audio/ui/beep.ogg",
	"lights_out": "res://assets/audio/ui/lights_out.ogg",
	"crash_1": "res://assets/audio/crash/crash_1.ogg",
	"crash_2": "res://assets/audio/crash/crash_2.ogg",
	"jingle": "res://assets/audio/music/jingle_win.ogg",
}
const POOL_SIZE := 8

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var stream := load(SOUNDS[key]) as AudioStream
		if stream != null:
			_streams[key] = stream
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func play(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(key):
		return
	var player := _free_player()
	player.stream = _streams[key]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]


# ------------------------------------------------------- named helpers


func click() -> void:
	play("click", -8.0)


func back() -> void:
	play("back", -8.0)


func toggle() -> void:
	play("toggle", -10.0)


func select() -> void:
	play("select", -10.0)


func open() -> void:
	play("open", -8.0)


func close() -> void:
	play("close", -8.0)


## One beep of the five-lamp start gantry.
func start_light() -> void:
	play("beep", -6.0)


## Green flag: the brighter "all lamps out" tone.
func lights_out() -> void:
	play("lights_out", -5.0)


## Chassis contact: strength 0..1 scales volume, random pitch hides repeats.
func crash(strength: float = 1.0) -> void:
	var key := "crash_1" if randf() < 0.5 else "crash_2"
	var db := clampf(remap(strength, 0.0, 1.0, -14.0, -2.0), -14.0, -2.0)
	play(key, db, randf_range(0.9, 1.1))


func finish() -> void:
	play("jingle", -5.0)
