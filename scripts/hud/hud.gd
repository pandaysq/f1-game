class_name Hud
extends CanvasLayer
## Time Trial HUD: speed, gear, lap counter, current/last/best lap, sectors.
## Big labels bottom corners so thumbs don't cover them on phones.

var _car: Car
var _session: TimeTrial

var _speed_label: Label
var _gear_label: Label
var _lap_label: Label
var _time_label: Label
var _best_label: Label
var _last_label: Label
var _sector_label: Label


func _init(car: Car, session: TimeTrial) -> void:
	_car = car
	_session = session

	var margin := 24
	_speed_label = _label(Vector2(margin, 40), 64)
	_speed_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_label.position = Vector2(margin, -140)
	_gear_label = _label(Vector2(margin, 40), 64)
	_gear_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_gear_label.position = Vector2(margin, -76)

	_time_label = _label_right(24, 44)
	_lap_label = _label(Vector2(margin, 40), 44)
	_lap_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lap_label.position = Vector2(margin, margin)

	_best_label = _label_right(84, 28)
	_last_label = _label_right(120, 28)
	_sector_label = _label_center_top(130, 36)

	session.lap_completed.connect(_on_lap_completed)
	session.sector_completed.connect(_on_sector_completed)


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


## Right-aligned label pinned to the top-right screen edge.
func _label_right(y: int, font_size: int) -> Label:
	var label := _label(Vector2.ZERO, font_size)
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.offset_left = -384.0
	label.offset_right = -24.0
	label.offset_top = float(y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


## Centered label pinned to the top edge (sector/lap flash messages).
func _label_center_top(y: int, font_size: int) -> Label:
	var label := _label(Vector2.ZERO, font_size)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -300.0
	label.offset_right = 300.0
	label.offset_top = float(y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _process(_delta: float) -> void:
	var speed_kmh := _car.linear_velocity.length() * 3.6
	_speed_label.text = "%d km/h" % int(speed_kmh)
	_gear_label.text = "R" if _car.powertrain.gear == 0 else str(_car.powertrain.gear)
	_time_label.text = _session.format_time(_session.current_lap_time)
	_lap_label.text = "LAP %d" % (_session.lap_count + 1)
	_best_label.text = "BEST  %s" % _session.format_time(_session.best_lap_time)
	_last_label.text = "LAST  %s" % _session.format_time(_session.last_lap_time)


func _on_lap_completed(lap_time: float, is_best: bool) -> void:
	_flash(
		_sector_label,
		"LAP %s%s" % [_session.format_time(lap_time), "  PERSONAL BEST" if is_best else ""]
	)


func _on_sector_completed(sector: int, time_s: float, is_best: bool) -> void:
	_flash(
		_sector_label,
		"S%d  %s%s" % [sector, _session.format_time(time_s), "  PB" if is_best else ""]
	)


func _flash(label: Label, message: String) -> void:
	label.text = message
	label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color.WHITE, 2.0)
