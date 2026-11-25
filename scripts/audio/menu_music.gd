class_name MenuMusic
extends Node
## Main-menu soundtrack (0.6.0): one seamless synth loop on the Music bus.
## Volume rides Settings.volumes["music"]; the node frees itself with the
## scene, so the race starts silent-but-for-the-engine.

const TRACK := "res://assets/audio/music/menu_loop.ogg"

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	var stream := load(TRACK) as AudioStreamOggVorbis
	if stream == null:
		push_warning("MenuMusic: stream missing, menu stays quiet")
		return
	stream.loop = true
	_player.stream = stream
	_player.bus = "Music"
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()


func stop() -> void:
	if _player != null:
		_player.stop()
