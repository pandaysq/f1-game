class_name TouchControls
extends CanvasLayer
## On-screen controls (0.4.0): F1-styled round buttons composed from
## Kenney Mobile Controls (CC0) + game-icons.net NOS bottle (CC BY 3.0),
## textures in assets/ui/controls. Steering arrows bottom-left, brake +
## throttle pedals and the nitro bottle bottom-right, pause top-right.
## TouchScreenButtons map to InputMap actions so the car reads them exactly
## like keyboard input. Visible on touch devices; APEX_TOUCH=1 forces them
## on for desktop QA screenshots.

signal pause_pressed

const BTN_SIZE := 256.0  # texture size

# texture paths per action: [normal, pressed]
const TEXTURES := {
	"steer_left":
	["res://assets/ui/controls/btn_left.png", "res://assets/ui/controls/btn_left_p.png"],
	"steer_right":
	["res://assets/ui/controls/btn_right.png", "res://assets/ui/controls/btn_right_p.png"],
	"throttle": ["res://assets/ui/controls/btn_gas.png", "res://assets/ui/controls/btn_gas_p.png"],
	"brake": ["res://assets/ui/controls/btn_brake.png", "res://assets/ui/controls/btn_brake_p.png"],
	"nitro": ["res://assets/ui/controls/btn_nitro.png", "res://assets/ui/controls/btn_nitro_p.png"],
}

# anchor fractions of the visible rect (x, y of the button center)
const LAYOUT := {
	"steer_left": Vector2(0.065, 0.80),
	"steer_right": Vector2(0.185, 0.80),
	"brake": Vector2(0.735, 0.80),
	"throttle": Vector2(0.865, 0.74),
	"nitro": Vector2(0.875, 0.575),
}

var _buttons: Dictionary = {}
var _pause_button: TextureButton
var _layout_next_ms := 0  # layout gate (0.10.2): buttons move on resize only


func _ready() -> void:
	var is_touch := DisplayServer.is_touchscreen_available()
	visible = is_touch or OS.get_environment("APEX_TOUCH") == "1"

	for action in TEXTURES:
		var paths: Array = TEXTURES[action]
		var b := TouchScreenButton.new()
		b.action = action
		b.texture_normal = load(paths[0])
		b.texture_pressed = load(paths[1])
		b.modulate = Color(1, 1, 1)
		b.shape_centered = false
		add_child(b)
		_buttons[action] = b

	_pause_button = TextureButton.new()
	_pause_button.texture_normal = load("res://assets/ui/controls/btn_pause.png")
	_pause_button.texture_pressed = load("res://assets/ui/controls/btn_pause_p.png")
	_pause_button.ignore_texture_size = true
	_pause_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_pause_button.custom_minimum_size = Vector2(56, 56)
	_pause_button.size = Vector2(56, 56)
	_pause_button.modulate = Color(1, 1, 1, 0.8)
	_pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	add_child(_pause_button)
	_layout_pause(Vector2(1280, 720))


func _process(_delta: float) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms < _layout_next_ms:
		return
	_layout_next_ms = now_ms + 250
	var rect := _visible_rect()
	var scale := clampf(rect.y / 720.0, 0.72, 1.15)
	for action in _buttons:
		var b: TouchScreenButton = _buttons[action]
		var center: Vector2 = LAYOUT[action]
		b.scale = Vector2(scale, scale)
		b.position = (
			Vector2(center.x * rect.x, center.y * rect.y) - Vector2.ONE * BTN_SIZE * scale * 0.5
		)
	_layout_pause(rect)


func _visible_rect() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout_pause(rect: Vector2) -> void:
	_pause_button.position = Vector2(rect.x - 76.0, 20.0)
	_pause_button.size = Vector2(56, 56)
