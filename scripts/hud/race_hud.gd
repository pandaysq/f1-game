class_name RaceHud
extends CanvasLayer
## Race HUD (0.9.0 restyle): F1-TV-look UI — position tower with the driver
## tag chip, DRS badge and tyre icon row, speed+gear strip, live standings
## tower with per-driver bar colors and 3-letter tags, start lights, icon
## flash messages and a proper race-result screen. "///" text separators and
## AI<N> labels are gone: DriverRoster names every grid slot, F1Theme.sep
## replaces string dividers. Big elements sit in corners so thumbs do not
## cover them on phones.

var start_lights: StartLights

var _car: Car
var _session: RaceSession
var _car_index := 0

var _pos_label: Label
var _lap_label: Label
var _drs_badge: PanelContainer
var _drs_label: Label
var _drs_state := -1
var _tyre_icon: TextureRect
var _tyre_icon_name := ""
var _tyre_label: Label
var _speed_label: Label
var _gear_label: Label
var _message_box: HBoxContainer
var _message_icon: TextureRect
var _message_label: Label
var _message_sub: Label
var _standings_box: VBoxContainer
var _standings_rows: Dictionary = {}  # car_index -> {pos, gap} labels
var _last_order: Array = []
var _results_root: Control
var _minimap: MiniMap
var _cars: Array = []


func _init(car: Car, session: RaceSession, car_index: int) -> void:
	_car = car
	_session = session
	_car_index = car_index

	# top-left tower: position + driver tag / lap / DRS badge + tyre
	var tower := PanelContainer.new()
	tower.add_theme_stylebox_override("panel", F1Theme.panel_style())
	tower.position = Vector2(24, 24)
	add_child(tower)
	var tower_box := VBoxContainer.new()
	tower_box.add_theme_constant_override("separation", 4)
	tower.add_child(tower_box)
	var pos_row := HBoxContainer.new()
	pos_row.add_theme_constant_override("separation", 12)
	tower_box.add_child(pos_row)
	_pos_label = _styled_label(38, "black", Color.WHITE)
	pos_row.add_child(_pos_label)
	var chip := PanelContainer.new()
	var chip_style := F1Theme.panel_style(Color(1, 1, 1, 0.06), DriverRoster.tower_color(car_index))
	chip_style.content_margin_left = 10.0
	chip_style.content_margin_right = 12.0
	chip_style.content_margin_top = 2.0
	chip_style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pos_row.add_child(chip)
	var tag_label := _styled_label(18, "bold", Color.WHITE)
	tag_label.text = DriverRoster.tag(car_index)
	chip.add_child(tag_label)
	_lap_label = _styled_label(20, "semibold", F1Theme.TEXT_DIM)
	tower_box.add_child(_lap_label)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	tower_box.add_child(status_row)
	_drs_badge = PanelContainer.new()
	var drs_style := StyleBoxFlat.new()
	drs_style.bg_color = Color(0.36, 0.36, 0.4, 0.7)
	drs_style.skew = Vector2(-0.35, 0)
	drs_style.content_margin_left = 12.0
	drs_style.content_margin_right = 12.0
	drs_style.content_margin_top = 2.0
	drs_style.content_margin_bottom = 2.0
	_drs_badge.add_theme_stylebox_override("panel", drs_style)
	status_row.add_child(_drs_badge)
	_drs_label = _styled_label(16, "bold", Color(1, 1, 1, 0.45))
	_drs_label.text = "DRS"
	_drs_badge.add_child(_drs_label)
	var tyre_row := HBoxContainer.new()
	tyre_row.add_theme_constant_override("separation", 7)
	status_row.add_child(tyre_row)
	_tyre_icon = UiIcons.icon("car-wheel", 18, F1Theme.TEXT_DIM)
	tyre_row.add_child(_tyre_icon)
	_tyre_label = _styled_label(16, "semibold", F1Theme.TEXT_DIM)
	_tyre_label.text = "100%"
	tyre_row.add_child(_tyre_label)

	# bottom-left strip: speed + gear
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

	# standings tower under the HUD tower: one slab per driver (0.9.0)
	_standings_box = VBoxContainer.new()
	_standings_box.add_theme_constant_override("separation", 3)
	_standings_box.position = Vector2(24, 178)
	add_child(_standings_box)

	_message_box = HBoxContainer.new()
	_message_box.anchor_left = 0.5
	_message_box.anchor_right = 0.5
	_message_box.offset_left = -340.0
	_message_box.offset_right = 340.0
	_message_box.offset_top = 248.0
	_message_box.offset_bottom = 308.0
	_message_box.grow_vertical = Control.GROW_DIRECTION_END
	_message_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_message_box.add_theme_constant_override("separation", 12)
	add_child(_message_box)
	_message_icon = UiIcons.icon("flag", 34, Color.WHITE)
	_message_icon.visible = false
	_message_box.add_child(_message_icon)
	_message_label = _styled_label(34, "black", Color.WHITE)
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_message_label.add_theme_constant_override("outline_size", 8)
	_message_box.add_child(_message_label)
	_message_sub = _styled_label(20, "semibold", F1Theme.TEXT_DIM)
	_message_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_message_box.add_child(_message_sub)

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
	_pos_label.text = "P%d" % pos
	var lap := clampi(_session.laps_completed[_car_index] + 1, 1, _session.total_laps)
	_lap_label.text = "LAP %d/%d" % [lap, _session.total_laps]
	_update_drs()
	_update_tyre()
	_update_standings()
	if _minimap != null:
		var positions: Array[Vector3] = []
		for c in _cars:
			positions.append((c as Car).global_transform.origin)
		_minimap.update_positions(positions)


## DRS badge: dim slab, yellow "ready", green "open" — broadcast style.
func _update_drs() -> void:
	var state := 2 if _car.drs_active else (1 if _session.drs_available(_car_index) else 0)
	if state == _drs_state:
		return
	_drs_state = state
	var sb: StyleBoxFlat = _drs_badge.get_theme_stylebox("panel")
	match state:
		1:
			sb.bg_color = F1Theme.YELLOW
			_drs_label.add_theme_color_override("font_color", F1Theme.DARK)
		2:
			sb.bg_color = Color(0.2, 0.95, 0.35)
			_drs_label.add_theme_color_override("font_color", F1Theme.DARK)
		_:
			sb.bg_color = Color(0.36, 0.36, 0.4, 0.7)
			_drs_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))


## Tyre readout: wheel icon while fresh, worn icon + color code when used up.
func _update_tyre() -> void:
	var tyre_pct := int(round((1.0 - _car.tire_wear_avg()) * 100.0))
	_tyre_label.text = "%d%%" % tyre_pct
	var wanted := "car-wheel" if tyre_pct >= 92 else "flat-tire"
	if wanted != _tyre_icon_name:
		_tyre_icon_name = wanted
		_tyre_icon.texture = UiIcons.texture(wanted)
	var color := F1Theme.TEXT_DIM
	if tyre_pct < 80:
		color = Color(1.0, 0.45, 0.1)
	elif tyre_pct < 92:
		color = F1Theme.YELLOW
	_tyre_label.add_theme_color_override("font_color", color)
	_tyre_icon.modulate = color


## Live standings: one slab per driver — pos, bar color, tag, lap count.
## Structure rebuilds only when the order changes; texts update per frame.
func _update_standings() -> void:
	var order := _session.positions()
	if order != _last_order:
		_last_order = order.duplicate()
		_rebuild_standings(order)
	for rank in range(order.size()):
		var i: int = order[rank]
		var row: Dictionary = _standings_rows.get(i, {})
		if row.is_empty():
			continue
		(row["pos"] as Label).text = "P%d" % (rank + 1)
		(row["gap"] as Label).text = "L%d" % int(_session.laps_completed[i])


func _rebuild_standings(order: Array) -> void:
	_standings_rows.clear()
	for child in _standings_box.get_children():
		_standings_box.remove_child(child)
		child.queue_free()
	for rank in range(order.size()):
		var i: int = order[rank]
		var is_player := i == _car_index
		var row := PanelContainer.new()
		var style := F1Theme.panel_style(
			Color(1, 1, 1, 0.05) if is_player else F1Theme.PANEL_BG,
			F1Theme.RED if is_player else Color(1, 1, 1, 0.14)
		)
		style.content_margin_left = 10.0
		style.content_margin_right = 12.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		var pos_label := _styled_label(13, "bold", F1Theme.TEXT_DIM)
		line.add_child(pos_label)
		var bar := ColorRect.new()
		bar.color = DriverRoster.tower_color(i)
		bar.custom_minimum_size = Vector2(4, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		var tag_label := _styled_label(14, "bold", Color.WHITE)
		tag_label.text = DriverRoster.tag(i)
		line.add_child(tag_label)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(spacer)
		var gap_label := _styled_label(13, "semibold", F1Theme.TEXT_DIM)
		line.add_child(gap_label)
		_standings_box.add_child(row)
		_standings_rows[i] = {"pos": pos_label, "gap": gap_label}


## Track map widget (0.6.0): built by the main scene once the track is known.
func attach_minimap(track: TrackData, cars: Array) -> void:
	_cars = cars
	_minimap = MiniMap.new(track.points)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-262, 86)
	add_child(_minimap)


## Center-top flash message: optional icon + text + dim sub-line.
func show_message(
	message: String,
	icon_name: String = "",
	sub: String = "",
	icon_color: Color = Color.WHITE,
	flash: Color = Color(1.0, 0.9, 0.2)
) -> void:
	_message_label.text = message
	_message_sub.text = sub
	_message_sub.visible = not sub.is_empty()
	_message_icon.visible = not icon_name.is_empty()
	if not icon_name.is_empty():
		_message_icon.texture = UiIcons.texture(icon_name)
		_message_icon.modulate = icon_color
	_message_label.modulate = flash
	var tween := create_tween()
	tween.tween_property(_message_label, "modulate", Color.WHITE, 2.0)


## Track-limits feedback (0.6.0): "TRACK LIMITS 1/3" flashes, third cut
## announces the deleted lap (red flag icon + LAP DELETED, 0.9.0 wording).
func show_track_limits(count: int, invalidated: bool = false) -> void:
	if invalidated:
		show_message(
			"LAP DELETED", "flag", "TRACK LIMITS", Color(1.0, 0.42, 0.3), Color(1.0, 0.35, 0.2)
		)
	else:
		show_message(
			"TRACK LIMITS %d/%d" % [count, TrackLimits.LIMITS_PER_LAP], "flag", "", F1Theme.YELLOW
		)


## F1-style classification screen after the finish. names: fictional driver
## roster of the current championship season (index 0 is the player, slot
## i maps to names[i]; empty in plain races -> base roster). champ:
## {standings, season_done, round_index} from ChampionshipStore.record_result
## — adds the points table (0.8.0).
func show_results(entries: Array, names: Array = [], champ: Dictionary = {}) -> void:
	if _results_root.visible:
		return
	var rows: VBoxContainer = _results_root.get_meta("rows")
	for child in rows.get_children():
		child.queue_free()
	var title: Label = _results_root.get_meta("title")
	title.text = "RACE RESULT"
	var laps: Label = _results_root.get_meta("title_laps")
	laps.text = "%d LAPS" % _session.total_laps

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
		line.add_theme_constant_override("separation", 12)
		row.add_child(line)
		line.add_child(_cell("P%d" % entry["position"], 22, "black"))
		var bar := ColorRect.new()
		bar.color = DriverRoster.tower_color(entry["car_index"])
		bar.custom_minimum_size = Vector2(4, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		line.add_child(_cell(DriverRoster.display_name(entry["car_index"], names), 20, "semibold"))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(spacer)
		line.add_child(UiIcons.icon("stopwatch", 16, F1Theme.TEXT_DIM))
		line.add_child(_cell(format_lap(entry["best_lap"]), 18, "regular"))
		rows.add_child(row)
	_show_championship_table(champ)
	var hint: Label = _results_root.get_meta("hint")
	hint.text = "EXIT VIA THE PAUSE MENU WHEN READY"
	_results_root.visible = true


## Championship points table under the classification (top 5 + the player's
## row when further down). champ empty in plain races -> section stays hidden.
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
	header.text = "CHAMPIONSHIP"
	var sub: Label = _results_root.get_meta("champ_sub")
	sub.text = "FINAL" if season_done else "AFTER ROUND %d" % (int(champ.get("round_index", 0)) + 1)
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

	var title_row := F1Theme.heading("RACE RESULT", 36, F1Theme.RED, "checkered-flag")
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(title_row)
	var title: Label = title_row.get_child(1)
	title_row.add_child(F1Theme.sep(F1Theme.RED, 26.0))
	var title_laps := _styled_label(20, "semibold", F1Theme.TEXT_DIM)
	title_laps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(title_laps)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)

	var champ_box := VBoxContainer.new()
	champ_box.add_theme_constant_override("separation", 3)
	champ_box.visible = false
	box.add_child(champ_box)
	var champ_header := HBoxContainer.new()
	champ_header.add_theme_constant_override("separation", 10)
	champ_header.alignment = BoxContainer.ALIGNMENT_CENTER
	champ_box.add_child(champ_header)
	champ_header.add_child(UiIcons.icon("trophy", 20, F1Theme.YELLOW))
	var champ_title := _styled_label(18, "black", F1Theme.YELLOW)
	champ_header.add_child(champ_title)
	champ_header.add_child(F1Theme.sep(F1Theme.YELLOW, 16.0))
	var champ_sub := _styled_label(15, "semibold", F1Theme.TEXT_DIM)
	champ_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	champ_header.add_child(champ_sub)
	var champ_rows := VBoxContainer.new()
	champ_rows.add_theme_constant_override("separation", 4)
	champ_box.add_child(champ_rows)

	var hint := _styled_label(16, "semibold", F1Theme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_results_root.set_meta("title", title)
	_results_root.set_meta("title_laps", title_laps)
	_results_root.set_meta("rows", rows)
	_results_root.set_meta("hint", hint)
	_results_root.set_meta("champ_box", champ_box)
	_results_root.set_meta("champ_title", champ_title)
	_results_root.set_meta("champ_sub", champ_sub)
	_results_root.set_meta("champ_rows", champ_rows)


func _cell(text: String, font_size: int, kind: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font(kind))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _styled_label(font_size: int, kind: String, color: Color) -> Label:
	var label := Label.new()
	label.text = "--"
	label.add_theme_font_override("font", F1Theme.font(kind))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Shared lap-time formatting (mm:ss.mmm).
static func format_lap(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.---"
	var minutes := int(seconds) / 60
	var rest := seconds - float(minutes * 60)
	return "%02d:%06.3f" % [minutes, rest]
