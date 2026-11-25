class_name CareerPanel
extends Control
## STATS screen (0.6.0): local career-lite totals (races / wins / podiums),
## best lap per track and the last recorded results. Reads CareerStore;
## F1-broadcast look matching the settings screen.

var _rows: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.9)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "STATS"
	title.add_theme_font_override("font", F1Theme.font("black"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", F1Theme.RED)
	box.add_child(title)

	var data := CareerStore.load_data()
	var races: Array = data.get(CareerStore.KEY_RACES, [])
	var stats := CareerStore.stats()
	if races.is_empty():
		var empty := Label.new()
		empty.text = "NO RACES YET  ///  GO RACE!"
		empty.add_theme_font_override("font", F1Theme.font("semibold"))
		empty.add_theme_font_size_override("font_size", 24)
		empty.add_theme_color_override("font_color", Color.WHITE)
		box.add_child(empty)
	else:
		box.add_child(_totals(stats))
		box.add_child(_best_laps(stats))
		box.add_child(_section("LAST RACES"))
		var recent := races.slice(maxi(races.size() - 6, 0))
		for r in recent:
			box.add_child(_race_row(r))

	box.add_child(_spacer(6))
	var back := F1Theme.button("BACK  [ESC]", 24, Vector2(220, 44))
	back.pressed.connect(_close)
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	Sfx.back()
	hide()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _cell(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("semibold"))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## RACES 8  ///  WINS 2  ///  PODIUMS 5 as one dark panel strip.
func _totals(stats: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", F1Theme.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	panel.add_child(row)
	row.add_child(_cell("RACES  %d" % int(stats.get("races", 0)), 24, Color.WHITE))
	row.add_child(_cell("WINS  %d" % int(stats.get("wins", 0)), 24, F1Theme.YELLOW))
	row.add_child(_cell("PODIUMS  %d" % int(stats.get("podiums", 0)), 24, F1Theme.GREEN))
	return panel


## Best lap per known track (only tracks with at least one timed race).
func _best_laps(stats: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", F1Theme.panel_style(F1Theme.PANEL_BG, F1Theme.PURPLE)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	panel.add_child(row)
	var best_by_track: Dictionary = stats.get("best_by_track", {})
	var any := false
	for t in Settings.TRACKS:
		var track_id := str(t.get("id", ""))
		if best_by_track.has(track_id):
			any = true
			row.add_child(
				_cell(
					(
						"%s  BEST  %s"
						% [track_id.to_upper(), RaceHud.format_lap(float(best_by_track[track_id]))]
					),
					20,
					Color.WHITE
				)
			)
	if not any:
		row.add_child(_cell("NO TIMED LAPS YET", 20, F1Theme.TEXT_DIM))
	return panel


func _race_row(r: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var position := int(r.get("position", 99))
	var edge := F1Theme.RED if position == 1 else Color(1, 1, 1, 0.3)
	panel.add_theme_stylebox_override("panel", F1Theme.panel_style(F1Theme.PANEL_BG, edge))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	var track_name := Settings.track_name(str(r.get("track", "")))
	var mode := "RACE" if str(r.get("mode", "race")) == "race" else "TT"
	row.add_child(_cell(mode, 18, F1Theme.TEXT_DIM))
	row.add_child(_cell("P%d/%d" % [position, int(r.get("car_count", 8))], 20, Color.WHITE))
	row.add_child(_cell(track_name, 18, Color.WHITE))
	var best := float(r.get("best_lap", -1.0))
	row.add_child(_cell("BEST  " + RaceHud.format_lap(best), 18, F1Theme.TEXT_DIM))
	row.add_child(_cell(str(r.get("date", "")), 16, F1Theme.TEXT_DIM))
	return panel
