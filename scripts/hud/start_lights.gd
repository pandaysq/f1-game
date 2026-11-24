class_name StartLights
extends Control
## F1 start lights: five red lamps on a dark gantry, top-center of the HUD.
## show_lights(0..5) during the countdown, lights_out() at the green flag —
## all lamps go dark (like the real gantry) and the widget hides itself.

const LAMP_RADIUS := 24.0
const LAMP_GAP := 10.0

var _lit := 0  # 0..5
var _hide_left := -1.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(5 * LAMP_RADIUS * 2 + 4 * LAMP_GAP + 24, 92)


func show_lights(count: int) -> void:
	var n := clampi(count, 0, 5)
	if n == _lit and visible:
		return
	_lit = n
	visible = true
	_hide_left = -1.0
	queue_redraw()


## Green flag: every lamp off (F1 gantry goes dark), fade the widget after 1 s.
func lights_out() -> void:
	_lit = 0
	_hide_left = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _hide_left > 0.0:
		_hide_left -= delta
		if _hide_left <= 0.0:
			visible = false


func _draw() -> void:
	var w := size.x
	var h := size.y
	# gantry slab
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.05, 0.05, 0.08, 0.92))
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, 5)), F1Theme.RED)
	var total := 5 * LAMP_RADIUS * 2 + 4 * LAMP_GAP
	var x0 := (w - total) * 0.5 + LAMP_RADIUS
	for i in range(5):
		var c := Vector2(x0 + i * (LAMP_RADIUS * 2 + LAMP_GAP), h * 0.55)
		if i < _lit:
			draw_circle(c, LAMP_RADIUS + 4.0, Color(1.0, 0.25, 0.15, 0.30))
			draw_circle(c, LAMP_RADIUS, F1Theme.RED)
			draw_circle(c + Vector2(-6, -6), 7.0, Color(1, 0.6, 0.5, 0.5))
		else:
			draw_circle(c, LAMP_RADIUS, Color(0.16, 0.05, 0.05))
		draw_arc(c, LAMP_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 2.0)
