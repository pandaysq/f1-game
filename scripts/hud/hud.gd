class_name Hud
extends CanvasLayer
## Time Trial HUD: speed/gear strip, lap counter, current/last/best lap panel
## with stopwatch icons, sector flash messages. Big elements in corners so
## thumbs don't cover them on phones. 0.6.0: track map + INVALID marker.
## 0.9.0: broadcast restyle — panel strip, icon timing rows, flag/stopwatch
## message icons, no string separators.

var _car: Car
var _session: TimeTrial
var _track_limits: TrackLimits
var _minimap: MiniMap

var _speed_label: Label
var _gear_label: Label
var _lap_label: Label
var _time_label: Label
var _best_label: Label
var _last_label: Label
var _message_box: HBoxContainer
var _message_icon: TextureRect
var _message_label: Label
var _message_sub: Label


func _init(car: Car, session: TimeTrial) -> void:
	_car = car
	_session = session

	var margin := 24
	_lap_label = _hud_label(44)
	add_child(_lap_label)
	_lap_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_lap_label.position = Vector2(margin, margin)

	# bottom-center strip: big speed, km/h + gear beside it (race-HUD look)
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", F1Theme.panel_style())
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = -100.0
	strip.offset_right = 100.0
	strip.offset_top = -110.0
	strip.offset_bottom = -18.0
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(strip)
	var strip_box := HBoxContainer.new()
	strip_box.add_theme_constant_override("separation", 18)
	strip.add_child(strip_box)
	_speed_label = _hud_label(64)
	strip_box.add_child(_speed_label)
	var unit_box := VBoxContainer.new()
	unit_box.add_theme_constant_override("separation", 0)
	strip_box.add_child(unit_box)
	var unit := _hud_label(18, "semibold", F1Theme.TEXT_DIM)
	unit.text = "km/h"
	unit_box.add_child(unit)
	_gear_label = _hud_label(34, "black", F1Theme.YELLOW)
	_gear_label.text = "N"
	unit_box.add_child(_gear_label)

	# top-right timing panel: current + best + last as icon+time rows
	var timing := PanelContainer.new()
	var timing_style := F1Theme.panel_style(F1Theme.PANEL_BG, Color(1, 1, 1, 0.35))
	timing_style.content_margin_top = 6.0
	timing_style.content_margin_bottom = 6.0
	timing.add_theme_stylebox_override("panel", timing_style)
	timing.anchor_left = 1.0
	timing.anchor_right = 1.0
	timing.offset_left = -460.0
	timing.offset_right = -100.0
	timing.offset_top = 24.0
	timing.grow_vertical = Control.GROW_DIRECTION_END
	add_child(timing)
	var timing_box := VBoxContainer.new()
	timing_box.add_theme_constant_override("separation", 4)
	timing.add_child(timing_box)
	_time_label = _hud_label(28)
	timing_box.add_child(_timing_row("stopwatch", 18, Color.WHITE, _time_label))
	_best_label = _hud_label(20, "semibold", F1Theme.PURPLE)
	timing_box.add_child(_timing_row("trophy", 15, F1Theme.PURPLE, _best_label))
	_last_label = _hud_label(20, "semibold", F1Theme.TEXT_DIM)
	timing_box.add_child(_timing_row("stopwatch", 15, F1Theme.TEXT_DIM, _last_label))

	_message_box = HBoxContainer.new()
	_message_box.anchor_left = 0.5
	_message_box.anchor_right = 0.5
	_message_box.offset_left = -340.0
	_message_box.offset_right = 340.0
	_message_box.offset_top = 130.0
	_message_box.offset_bottom = 190.0
	_message_box.grow_vertical = Control.GROW_DIRECTION_END
	_message_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_message_box.add_theme_constant_override("separation", 12)
	add_child(_message_box)
	_message_icon = UiIcons.icon("flag", 34, Color.WHITE)
	_message_icon.visible = false
	_message_box.add_child(_message_icon)
	_message_label = _hud_label(36)
	_message_box.add_child(_message_label)
	_message_sub = _hud_label(20, "semibold", F1Theme.TEXT_DIM)
	_message_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_message_box.add_child(_message_sub)

	session.lap_completed.connect(_on_lap_completed)
	session.sector_completed.connect(_on_sector_completed)


## Label factory over the 3D view: white with a dark outline by default.
## Pure factory — the caller parents the label (Godot 4 add_child never
## reparents, so auto-adding here would block container add_child calls).
func _hud_label(font_size: int, kind: String = "black", color: Color = Color(1, 1, 1)) -> Label:
	var label := Label.new()
	label.text = "--"
	label.add_theme_font_override("font", F1Theme.font(kind))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	return label


## [icon][value] row used inside the timing panel; label is created by the
## caller so _process can update it directly.
func _timing_row(icon_name: String, size: float, color: Color, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiIcons.icon(icon_name, size, color))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return row


func _process(_delta: float) -> void:
	var speed_kmh := _car.linear_velocity.length() * 3.6
	_speed_label.text = "%d" % int(speed_kmh)
	_gear_label.text = "R" if _car.powertrain.gear == 0 else str(_car.powertrain.gear)
	var lap_time_text := _session.format_time(_session.current_lap_time)
	if _track_limits != null and not _track_limits.lap_valid():
		lap_time_text += "  INVALID"
		_time_label.add_theme_color_override("font_color", F1Theme.RED)
	else:
		_time_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_time_label.text = lap_time_text
	_lap_label.text = "LAP %d" % (_session.lap_count + 1)
	_best_label.text = _session.format_time(_session.best_lap_time)
	_last_label.text = _session.format_time(_session.last_lap_time)
	if _minimap != null:
		var positions: Array[Vector3] = [_car.global_transform.origin]
		_minimap.update_positions(positions)


## Track map widget + lap-validity source, wired by the main scene (0.6.0).
func attach_context(track: TrackData, limits: TrackLimits) -> void:
	_track_limits = limits
	_minimap = MiniMap.new(track.points)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-262, 160)
	add_child(_minimap)


## Center-top flash message: optional icon + text + dim sub-line.
func show_message(message: String, icon_name: String = "", sub: String = "") -> void:
	_message_label.text = message
	_message_sub.text = sub
	_message_sub.visible = not sub.is_empty()
	_message_icon.visible = not icon_name.is_empty()
	if not icon_name.is_empty():
		_message_icon.texture = UiIcons.texture(icon_name)
	_message_label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate", Color.WHITE, 2.0)


func show_invalid_lap() -> void:
	show_message("LAP INVALID", "flag", "TRACK LIMITS")
	_message_icon.modulate = Color(1.0, 0.42, 0.3)


func _on_lap_completed(lap_time: float, is_best: bool) -> void:
	show_message(_session.format_time(lap_time), "stopwatch", "PERSONAL BEST" if is_best else "")
	if is_best:
		_message_icon.modulate = F1Theme.PURPLE


func _on_sector_completed(sector: int, time_s: float, is_best: bool) -> void:
	show_message(
		"S%d  %s" % [sector, _session.format_time(time_s)], "stopwatch", "PB" if is_best else ""
	)
