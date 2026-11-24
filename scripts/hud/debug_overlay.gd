extends CanvasLayer
## Debug overlay (F3): FPS, physics tick rate, basic engine stats.
## Hidden by default (APEX_DEBUG=1 to show); expanded in later phases with
## wheel slip, aero values, network stats.

var label: Label

var _frames: int = 0
var _elapsed: float = 0.0
var _fps: int = 0


func _ready() -> void:
	label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
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
	label.text = (
		"FPS: %d | Physics: %d Hz | Quality: %s"
		% [_fps, Engine.physics_ticks_per_second, Settings.quality]
	)
