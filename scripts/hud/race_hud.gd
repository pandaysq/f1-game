class_name RaceHud
extends CanvasLayer
## Race HUD (Phase 2): speed, gear, position, lap counter, DRS state,
## countdown/flash messages. Big labels in the bottom corners so thumbs
## do not cover them on phones.

var _car: Car
var _session: RaceSession
var _car_index := 0

var _speed_label: Label
var _gear_label: Label
var _pos_label: Label
var _lap_label: Label
var _message_label: Label
var _drs_label: Label
var _standings_label: Label


func _init(car: Car, session: RaceSession, car_index: int) -> void:
	_car = car
	_session = session
	_car_index = car_index

	var margin := 24
	_speed_label = _label(Vector2(margin, 40), 64)
	_speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_label.position = Vector2(margin, -140)
	_gear_label = _label(Vector2(margin, 40), 64)
	_gear_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_gear_label.position = Vector2(margin, -76)

	_pos_label = _label(Vector2(margin, 40), 54)
	_pos_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pos_label.position = Vector2(margin, margin)
	_lap_label = _label(Vector2(margin, 40), 44)
	_lap_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lap_label.position = Vector2(margin, margin + 64)
	_drs_label = _label(Vector2(margin, 40), 34)
	_drs_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_drs_label.position = Vector2(margin, margin + 116)
	_drs_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	_drs_label.text = "DRS"

	_message_label = _label_center_top(140, 48)
	_standings_label = _label_right(24, 24)
	_standings_label.position = Vector2(-400, 72)
	_standings_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_standings_label.position = Vector2(-384, 72)


func _process(_delta: float) -> void:
	var speed_kmh := _car.linear_velocity.length() * 3.6
	_speed_label.text = "%d km/h" % int(speed_kmh)
	_gear_label.text = "R" if _car.powertrain.gear == 0 else str(_car.powertrain.gear)
	var pos := _session.position_of(_car_index)
	_pos_label.text = "P%d/%d" % [pos, _session.car_count]
	var lap := clampi(_session.laps_completed[_car_index] + 1, 1, _session.total_laps)
	_lap_label.text = "LAP %d/%d" % [lap, _session.total_laps]
	if _car.drs_active:
		_drs_label.text = "DRS OPEN"
		_drs_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	elif _session.drs_available(_car_index):
		_drs_label.text = "DRS READY  [E]"
		_drs_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		_drs_label.text = "DRS"
		_drs_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_standings_label.text = _standings_text()


func _standings_text() -> String:
	var order := _session.positions()
	var text := ""
	for rank in range(order.size()):
		var i: int = order[rank]
		var mark := ">" if i == _car_index else " "
		var name := "YOU" if i == 0 else "AI%d" % i
		var lap_str := str(_session.laps_completed[i])
		text += "%s P%d %-4s L%s\n" % [mark, rank + 1, name, lap_str]
	return text


func show_message(message: String) -> void:
	_message_label.text = message
	_message_label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate", Color.WHITE, 2.0)


func _label(pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = "--"
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.position = pos
	add_child(label)
	return label


func _label_center_top(y: int, font_size: int) -> Label:
	var label := _label(Vector2.ZERO, font_size)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -300.0
	label.offset_right = 300.0
	label.offset_top = float(y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Right-aligned small standings block pinned near the top-right edge.
func _label_right(y: int, font_size: int) -> Label:
	var label := _label(Vector2.ZERO, font_size)
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -384.0
	label.offset_right = -24.0
	label.offset_top = float(y)
	return label
