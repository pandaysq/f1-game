class_name TouchControls
extends CanvasLayer
## On-screen controls for mobile (Phase 1): steering left/right, throttle,
## brake, nitro. Mapped to InputMap actions so the car reads them exactly
## like keyboard input. Visible on touch devices; toggled with a debug key
## otherwise (desktop testing via mouse touch emulation).

var visible_on_touch_only: bool = true

var _left_button: TouchScreenButton
var _right_button: TouchScreenButton
var _throttle_button: TouchScreenButton
var _brake_button: TouchScreenButton
var _nitro_button: TouchScreenButton


func _ready() -> void:
	var screen_size := Vector2(1280, 720)
	var is_touch := DisplayServer.is_touchscreen_available()
	visible = not visible_on_touch_only or is_touch

	# left cluster: steering
	_left_button = _button("steer_left", Color(0.9, 0.9, 0.95, 0.35))
	_left_button.position = screen_size * Vector2(0.08, 0.82)
	_right_button = _button("steer_right", Color(0.9, 0.9, 0.95, 0.35))
	_right_button.position = screen_size * Vector2(0.22, 0.82)

	# right cluster: throttle + brake, nitro above
	_throttle_button = _button("throttle", Color(0.2, 0.85, 0.3, 0.35))
	_throttle_button.position = screen_size * Vector2(0.88, 0.72)
	_brake_button = _button("brake", Color(0.9, 0.2, 0.2, 0.35))
	_brake_button.position = screen_size * Vector2(0.76, 0.82)
	_nitro_button = _button("nitro", Color(0.95, 0.8, 0.2, 0.35))
	_nitro_button.position = screen_size * Vector2(0.88, 0.52)

	# small labels under buttons
	_caption("THROTTLE", _throttle_button.position + Vector2(0, 96))
	_caption("BRAKE", _brake_button.position + Vector2(0, 96))
	_caption("NITRO", _nitro_button.position + Vector2(0, 96))


## Creates a TouchScreenButton with a procedurally generated rounded square.
func _button(action: String, color: Color) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.action = action
	button.texture_normal = _rounded_texture(color)
	button.texture_pressed = _rounded_texture(Color(color, minf(color.a + 0.25, 0.9)))
	button.modulate = Color(1, 1, 1)
	button.scale = Vector2(0.85, 0.85)
	add_child(button)
	return button


func _rounded_texture(color: Color) -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var edge := 16
			var inside := true
			var dx := minf(float(x), float(size - 1 - x))
			var dy := minf(float(y), float(size - 1 - y))
			if x < edge or x >= size - edge:
				if dx + dy < edge:
					inside = false
			if y < edge or y >= size - edge:
				if dx + dy < edge:
					inside = false
			image.set_pixel(x, y, color if inside else Color(color, 0.0))
	return ImageTexture.create_from_image(image)


func _caption(text: String, pos: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.position = pos - Vector2(40, 0)
	add_child(label)
