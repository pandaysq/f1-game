class_name RaceHud
extends CanvasLayer
## Race HUD (0.4.0 restyle): F1-TV-look UI — position/lap/DRS tower with a
## red edge, speed+gear strip, live standings panel, start lights, flash
## messages and a proper race-result screen. Big elements sit in corners so
## thumbs do not cover them on phones.

var start_lights: StartLights

var _car: Car
var _session: RaceSession
var _car_index := 0

var _pos_label: Label
var _lap_label: Label
var _drs_label: Label
var _tyre_label: Label
var _speed_label: Label
var _gear_label: Label
var _message_label: Label
var _standings_label: Label
var _results_root: Control
var _minimap: MiniMap
var _cars: Array = []


func _init(car: Car, session: RaceSession, car_index: int) -> void:
	_car = car
	_session = session
	_car_index = car_index

	# top-left tower: position / lap / DRS
	var tower := PanelContainer.new()
	tower.add_theme_stylebox_override("panel", F1Theme.panel_style())
	tower.position = Vector2(24, 24)
	add_child(tower)
	var tower_box := VBoxContainer.new()
	tower_box.add_theme_constant_override("separation", 2)
	tower.add_child(tower_box)
	_pos_label = _styled_label(38, "black", Color.WHITE)
	_lap_label = _styled_label(22, "semibold", F1Theme.TEXT_DIM)
	_drs_label = _styled_label(20, "bold", Color(0.45, 0.45, 0.45))
	tower_box.add_child(_pos_label)
	tower_box.add_child(_lap_label)
	tower_box.add_child(_drs_label)
	_drs_label.text = "DRS"
	_tyre_label = _styled_label(16, "semibold", F1Theme.TEXT_DIM)
	_tyre_label.text = "TYRE 100%"
	tower_box.add_child(_tyre_label)

	# bottom-left strip: speed + gear
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", F1Theme.panel_style())
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	strip.offset_top = -110.0
	strip.offset_bottom = -18.0
	add_child(strip)
	var strip_box := HBoxContainer.new()
	strip_box.add_theme_constant_override("separation", 18)
	strip.add_child(strip_box)
	_speed_label = _styled_label(64, "black", Color.WHITE)
	strip_box.add_child(_speed_label)
	var unit_box := VBoxContainer.new()
	unit_box.add_theme_constant_override("separation", 0)
	strip_box.add_child(unit_box)
	var unit := _styled_label(18, "semibold", F1Theme.TEXT_DIM)
	unit.text = "km/h"
	unit_box.add_child(unit)
	_gear_label = _styled_label(34, "black", F1Theme.YELLOW)
	_gear_label.text = "N"
	unit_box.add_child(_gear_label)

	# top-right: track map (0.6.0), standings moved under the tower
	var standings := PanelContainer.new()
	standings.add_theme_stylebox_override(
		"panel", F1Theme.panel_style(F1Theme.PANEL_BG, Color(1, 1, 1, 0.35))
	)
	standings.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	standings.position = Vector2(24, 178)
	add_child(standings)
	_standings_label = _styled_label(16, "semibold", Color.WHITE)
	standings.add_child(_standings_label)
	_message_label = _label_center_top(248, 52)
	start_lights = StartLights.new()
	start_lights.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	start_lights.anchor_left = 0.5
	start_lights.anchor_right = 0.5
	start_lights.offset_left = -220
	start_lights.offset_right = 220
	start_lights.offset_top = 110
	add_child(start_lights)
	_build_results_screen()


func _process(_delta: float) -> void:
	var speed_kmh := _car.linear_velocity.length() * 3.6
	_speed_label.text = "%d" % int(speed_kmh)
	_gear_label.text = "R" if _car.powertrain.gear == 0 else str(_car.powertrain.gear)
	var pos := _session.position_of(_car_index)
	_pos_label.text = "P%d/%d" % [pos, _session.car_count]
	var lap := clampi(_session.laps_completed[_car_index] + 1, 1, _session.total_laps)
	_lap_label.text = "LAP %d/%d" % [lap, _session.total_laps]
	if _car.drs_active:
		_drs_label.text = "DRS OPEN"
		_drs_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.2))
	elif _session.drs_available(_car_index):
		_drs_label.text = "DRS READY"
		_drs_label.add_theme_color_override("font_color", F1Theme.YELLOW)
	else:
		_drs_label.text = "DRS"
		_drs_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	var tyre_pct := int(round((1.0 - _car.tire_wear_avg()) * 100.0))
	_tyre_label.text = "TYRE %d%%" % tyre_pct
	if tyre_pct < 80:
		_tyre_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.1))
	elif tyre_pct < 92:
		_tyre_label.add_theme_color_override("font_color", F1Theme.YELLOW)
	else:
		_tyre_label.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	_standings_label.text = _standings_text()
	if _minimap != null:
		var positions: Array[Vector3] = []
		for c in _cars:
			positions.append((c as Car).global_transform.origin)
		_minimap.update_positions(positions)


## Track map widget (0.6.0): built by the main scene once the track is known.
func attach_minimap(track: TrackData, cars: Array) -> void:
	_cars = cars
	_minimap = MiniMap.new(track.points)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-262, 86)
	add_child(_minimap)


func show_message(message: String) -> void:
	_message_label.text = message
	_message_label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate", Color.WHITE, 2.0)


## Track-limits feedback (0.6.0): "TRACK LIMITS 1/3" flashes, third cut
## announces the deleted lap.
func show_track_limits(count: int, invalidated: bool = false) -> void:
	if invalidated:
		show_message("TRACK LIMITS  ///  LAP DELETED")
		_message_label.modulate = Color(1.0, 0.25, 0.1)
	else:
		show_message("TRACK LIMITS %d/%d" % [count, TrackLimits.LIMITS_PER_LAP])


## F1-style classification screen after the finish. names: fictional driver
## roster of the current championship season (index 0 is the player, slot
## i maps to names[i]; empty in plain races → YOU / AI<i>). champ:
## {standings, season_done, round_index} from ChampionshipStore.record_result
## — adds the points table (0.8.0).
func show_results(entries: Array, names: Array = [], champ: Dictionary = {}) -> void:
	if _results_root.visible:
		return
	var rows: VBoxContainer = _results_root.get_meta("rows")
	for child in rows.get_children():
		child.queue_free()
	var title: Label = _results_root.get_meta("title")
	title.text = "RACE RESULT  ///  %d LAPS" % _session.total_laps

	for entry in entries:
		var is_player: bool = entry["car_index"] == 0
		var row := PanelContainer.new()
		row.add_theme_stylebox_override(
			"panel",
			F1Theme.panel_style(
				F1Theme.RED if is_player else F1Theme.PANEL_BG,
				F1Theme.RED if is_player else Color(1, 1, 1, 0.3)
			)
		)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 26)
		row.add_child(line)
		line.add_child(_cell("P%d" % entry["position"], 22, "black"))
		line.add_child(_cell(_driver_label(entry["car_index"], is_player, names), 20, "semibold"))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(spacer)
		line.add_child(_cell("BEST  " + format_lap(entry["best_lap"]), 18, "regular"))
		rows.add_child(row)
	_show_championship_table(champ)
	var hint: Label = _results_root.get_meta("hint")
	hint.text = "PAUSE  >  EXIT TO MENU  when ready"
	_results_root.visible = true


## Grid-slot label: season roster names (index 0 is the player) when
## available, fallback YOU / AI<i>.
func _driver_label(car_index: int, is_player: bool, names: Array) -> String:
	if is_player:
		return "YOU"
	if car_index >= 0 and car_index < names.size():
		return str(names[car_index])
	return "AI%d" % car_index


## Championship points table under the classification (top 5 + the player's
## row when further down). champ empty in plain races → section stays hidden.
func _show_championship_table(champ: Dictionary) -> void:
	var box: VBoxContainer = _results_root.get_meta("champ_box")
	var rows_box: VBoxContainer = _results_root.get_meta("champ_rows")
	for child in rows_box.get_children():
		child.queue_free()
	box.visible = not champ.is_empty()
	if champ.is_empty():
		return
	var season_done := bool(champ.get("season_done", false))
	var header: Label = _results_root.get_meta("champ_title")
	header.text = (
		"CHAMPIONSHIP  ///  FINAL"
		if season_done
		else "CHAMPIONSHIP  ///  AFTER ROUND %d" % (int(champ.get("round_index", 0)) + 1)
	)
	var standings: Array = champ.get("standings", [])
	var shown := 0
	for i in range(standings.size()):
		var entry: Dictionary = standings[i]
		var name := str(entry.get("name", "?"))
		var is_player := name == ChampionshipStore.PLAYER_NAME
		if shown >= 5 and not is_player:
			continue
		rows_box.add_child(
			_champ_row("P%d" % (i + 1), name, "%d PTS" % int(entry.get("points", 0)), is_player)
		)
		shown += 1


func _champ_row(position: String, name: String, points: String, is_player: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override(
		"panel",
		F1Theme.panel_style(
			F1Theme.RED if is_player else F1Theme.PANEL_BG,
			F1Theme.RED if is_player else Color(1, 1, 1, 0.3)
		)
	)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 18)
	row.add_child(line)
	line.add_child(_cell(position, 16, "black"))
	line.add_child(_cell(name, 15, "semibold"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)
	line.add_child(_cell(points, 15, "regular"))
	return row


func _build_results_screen() -> void:
	_results_root = Control.new()
	_results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_root.visible = false
	add_child(_results_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.8)
	_results_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := _styled_label(36, "black", F1Theme.RED)
	title.text = "RACE RESULT"
	box.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)

	var champ_box := VBoxContainer.new()
	champ_box.add_theme_constant_override("separation", 3)
	champ_box.visible = false
	box.add_child(champ_box)
	var champ_title := _styled_label(18, "black", F1Theme.YELLOW)
	champ_box.add_child(champ_title)
	var champ_rows := VBoxContainer.new()
	champ_rows.add_theme_constant_override("separation", 4)
	champ_box.add_child(champ_rows)

	var hint := _styled_label(18, "semibold", F1Theme.TEXT_DIM)
	box.add_child(hint)

	_results_root.set_meta("title", title)
	_results_root.set_meta("rows", rows)
	_results_root.set_meta("hint", hint)
	_results_root.set_meta("champ_box", champ_box)
	_results_root.set_meta("champ_title", champ_title)
	_results_root.set_meta("champ_rows", champ_rows)


func _cell(text: String, font_size: int, kind: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font(kind))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _standings_text() -> String:
	var order := _session.positions()
	var text := ""
	for rank in range(order.size()):
		var i: int = order[rank]
		var mark := "> " if i == _car_index else "   "
		var name := "YOU" if i == 0 else "AI%d" % i
		var lap_str := str(_session.laps_completed[i])
		text += "%sP%d  %-4s  L%s\n" % [mark, rank + 1, name, lap_str]
	return text


func _styled_label(font_size: int, kind: String, color: Color) -> Label:
	var label := Label.new()
	label.text = "--"
	label.add_theme_font_override("font", F1Theme.font(kind))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _label_center_top(y: int, font_size: int) -> Label:
	var label := _styled_label(font_size, "black", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -300.0
	label.offset_right = 300.0
	label.offset_top = float(y)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	return label


## Shared lap-time formatting (mm:ss.mmm).
static func format_lap(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.---"
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes * 60)
	return "%02d:%06.3f" % [minutes, rest]
