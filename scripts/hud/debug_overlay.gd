extends CanvasLayer
## Debug overlay (F3): FPS, physics tick rate, basic engine stats.
## Expanded in later phases with wheel slip, aero values, network stats.

var _frames: int = 0
var _elapsed: float = 0.0
var _fps: int = 0

@onready var label: Label = $Label


func _ready() -> void:
	_refresh()


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _elapsed >= 0.5:
		_fps = int(round(float(_frames) / _elapsed))
		_frames = 0
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	label.text = "FPS: %d | Physics: %d Hz | Quality: %s" % [
		_fps, Engine.physics_ticks_per_second, Settings.quality
	]
