class_name ChampionshipPanel
extends Control
## CHAMPIONSHIP screen (0.8.0): offline season setup, schedule with results,
## live standings and round launch. Three states — no season (NEW SEASON
## setup with rounds / laps / difficulty), active season (round list +
## standings + START ROUND), finished season (final table + champion).
## Autoload-free _init so headless --script checks can instantiate it; the
## menu injects Settings.TRACKS / LAP_CHOICES / AI_LEVELS through
## setup_catalog() before showing.

var _store := ChampionshipStore.new()
var _catalog: Array = []  # Settings.TRACKS entries {id, name, path}
var _lap_choices: Array = []  # Settings.LAP_CHOICES
var _level_choices: Array = []  # Settings.AI_LEVELS

var _round_buttons: Dictionary = {}
var _tyre_buttons: Dictionary = {}
var _tyre_current := TyreCompound.DEFAULT_COMPOUND
var _lap_buttons: Dictionary = {}
var _level_buttons: Dictionary = {}
var _picked_round := 4
var _picked_laps := 5
var _picked_level := "pro"

var _confirm_abandon := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## Injects menu data (called by main_menu with Settings.TRACKS / LAP_CHOICES
## / AI_LEVELS) so the panel itself stays autoload-free for headless checks.
func setup_catalog(catalog: Array, lap_choices: Array, level_choices: Array) -> void:
	_catalog = catalog
	_lap_choices = lap_choices
	_level_choices = level_choices


## Current player compound for the YOUR TYRES row (injected by main_menu
## from Settings.race — the panel itself stays autoload-free).
func setup_tyres(current: String) -> void:
	_tyre_current = TyreCompound.sanitize(current)


## Replaces the default store (headless checks inject a temp-path instance
## so the real user:// season file is never touched).
func setup_store(store: ChampionshipStore) -> void:
	_store = store


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	Sfx.back()
	hide()


## Rebuilds the whole panel content for the current store state. The abandon
## confirm state survives the rebuild on the arming tap (keep_confirm).
func rebuild(keep_confirm: bool = false) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if not keep_confirm:
		_confirm_abandon = false
	_round_buttons.clear()
	_lap_buttons.clear()
	_level_buttons.clear()
	_tyre_buttons.clear()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.9)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)

	var round_info := _store.next_round()
	var state := _store.state()
	if state.is_empty():
		_build_setup(box)
	elif bool(state.get("done", false)):
		_build_finished(box, state)
	else:
		_build_active(box, state, round_info)


## ------------------------------------------------------------- state: setup


func _build_setup(box: VBoxContainer) -> void:
	box.add_child(_title("CHAMPIONSHIP"))
	box.add_child(_subtitle("OFFLINE SEASON"))
	box.add_child(_section("NEW SEASON"))
	var rounds: Array = []
	for v in ChampionshipStore.ROUND_CHOICES:
		rounds.append(str(v))
	box.add_child(_choice_row("ROUNDS", rounds, _round_buttons, _pick_round, str(_picked_round)))
	var laps: Array = []
	for v in _lap_choices:
		laps.append(str(v))
	box.add_child(_choice_row("LAPS PER ROUND", laps, _lap_buttons, _pick_laps, str(_picked_laps)))
	box.add_child(
		_choice_row("AI DIFFICULTY", _level_choices, _level_buttons, _pick_level, _picked_level)
	)

	var start := F1Theme.button("START SEASON", 30, Vector2(380, 58))
	start.pressed.connect(_start_season)
	box.add_child(start)
	box.add_child(_back_button())


## ------------------------------------------------------------- state: active


func _build_active(box: VBoxContainer, state: Dictionary, round_info: Dictionary) -> void:
	var schedule: Array = state.get("schedule", [])
	box.add_child(_title("CHAMPIONSHIP"))
	box.add_child(
		_subtitle("ROUND %d OF %d" % [int(round_info.get("index", 0)) + 1, schedule.size()])
	)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	columns.add_child(right)

	left.add_child(_section("CALENDAR"))
	var weather: Array = state.get("weather", [])
	for i in range(schedule.size()):
		var kind := WeatherState.DEFAULT_TYPE
		if i < weather.size():
			kind = WeatherState.sanitize(str(weather[i]))
		(
			left
			. add_child(
				_schedule_row(
					i,
					str(schedule[i]),
					kind,
					_store.player_results(),
					i == int(round_info.get("index", 0)),
				)
			)
		)
	right.add_child(_section("STANDINGS"))
	var table := _store.standings()
	if table.is_empty():
		right.add_child(_hint("NO POINTS YET"))
	for i in range(table.size()):
		right.add_child(_standing_row(i, table[i]))

	box.add_child(
		_choice_row("YOUR TYRES", TyreCompound.COMPOUNDS, _tyre_buttons, _pick_tyre, _tyre_current)
	)
	var round_kind := WeatherState.sanitize(str(round_info.get("weather", "dry")))
	var weather_row := HBoxContainer.new()
	weather_row.alignment = BoxContainer.ALIGNMENT_CENTER
	weather_row.add_theme_constant_override("separation", 10)
	weather_row.add_child(UiIcons.icon(WeatherState.icon(round_kind), 18, Color(0.62, 0.72, 0.92)))
	weather_row.add_child(_cell(WeatherState.label(round_kind), 16, F1Theme.TEXT_DIM))
	box.add_child(weather_row)
	box.add_child(_spacer(2))
	var start_label := "START ROUND %d" % (int(round_info.get("index", 0)) + 1)
	var start := F1Theme.button(start_label, 24, Vector2(560, 50))
	start.pressed.connect(_start_round)
	box.add_child(start)
	box.add_child(_abandon_button())
	box.add_child(_back_button())


## ------------------------------------------------------------- state: done


func _build_finished(box: VBoxContainer, state: Dictionary) -> void:
	var schedule: Array = state.get("schedule", [])
	var table := _store.standings()
	var champion := "YOU"
	if not table.is_empty():
		champion = str(table[0].get("name", "YOU"))
	box.add_child(_title("SEASON COMPLETE"))
	var champ_row := HBoxContainer.new()
	champ_row.add_theme_constant_override("separation", 14)
	champ_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(champ_row)
	champ_row.add_child(UiIcons.icon("trophy", 28, F1Theme.YELLOW))
	champ_row.add_child(_cell("CHAMPION", 16, F1Theme.TEXT_DIM))
	champ_row.add_child(F1Theme.sep(F1Theme.YELLOW, 20.0))
	champ_row.add_child(_cell(champion, 26, Color.WHITE))
	box.add_child(_section("FINAL STANDINGS"))
	for i in range(table.size()):
		box.add_child(_standing_row(i, table[i]))
	box.add_child(_spacer(4))
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 12)
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(info_row)
	info_row.add_child(F1Theme.chip("SEASON %s" % str(state.get("season_key", "")).to_upper()))
	info_row.add_child(F1Theme.sep(F1Theme.RED, 16.0))
	info_row.add_child(F1Theme.chip("%d ROUNDS" % schedule.size()))
	info_row.add_child(F1Theme.sep(F1Theme.RED, 16.0))
	info_row.add_child(
		F1Theme.chip("%s AI" % str(state.get("difficulty", "pro")).to_upper(), 15, Color.WHITE)
	)
	var again := F1Theme.button("NEW SEASON", 30, Vector2(380, 58))
	again.pressed.connect(
		func() -> void:
			_store.abandon()
			Sfx.open()
			rebuild()
	)
	box.add_child(again)
	box.add_child(_back_button())


## ------------------------------------------------------------- actions


func _pick_round(value: String) -> void:
	_picked_round = int(value)


func _pick_laps(value: String) -> void:
	_picked_laps = int(value)


func _pick_level(value: String) -> void:
	_picked_level = value


func _pick_tyre(value: String) -> void:
	_tyre_current = TyreCompound.sanitize(value)
	Settings.race["tyre"] = _tyre_current
	Settings.save_settings()


func _start_season() -> void:
	if _store.new_season(_picked_round, _picked_level, _picked_laps, _catalog):
		Sfx.open()
		rebuild()


func _start_round() -> void:
	var round_info := _store.next_round()
	if round_info.is_empty():
		return
	Settings.race["track"] = str(round_info.get("track_id", Settings.DEFAULT_TRACK))
	Settings.race["laps"] = int(round_info.get("laps", 5))
	Settings.race["difficulty"] = str(round_info.get("difficulty", "pro"))
	Settings.race["weather"] = WeatherState.sanitize(str(round_info.get("weather", "dry")))
	Settings.launch_mode = "championship"
	Settings.save_settings()
	Sfx.select()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _abandon_button() -> Button:
	var label := "ABANDON SEASON" if not _confirm_abandon else "SURE? TAP AGAIN TO ABANDON"
	var b := F1Theme.button(label, 20, Vector2(560, 38))
	if _confirm_abandon:
		b.modulate = Color(1.0, 0.55, 0.55)
	b.pressed.connect(
		func() -> void:
			if not _confirm_abandon:
				_confirm_abandon = true
				Sfx.click()
				rebuild(true)
				return
			_store.abandon()
			Sfx.back()
			rebuild()
	)
	return b


func _back_button() -> HBoxContainer:
	return F1Theme.back_row(_close, 20, Vector2(300, 36))


## ------------------------------------------------------------- widgets


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("black"))
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", F1Theme.RED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("semibold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	return l


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("semibold"))
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Choice chips in the RaceSetup style: label + one row of buttons. values
## is untyped so injected Settings arrays pass through without copies.
func _choice_row(
	label: String, values: Array, registry: Dictionary, on_pick: Callable, current: String
) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section(label))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var labels: Array = []
	for value in values:
		labels.append(String(value).to_upper())
	var width := F1Theme.fit_width(labels, 20, 86.0)
	for value in values:
		var b := F1Theme.button(String(value).to_upper(), 20, Vector2(width, 42))
		b.toggle_mode = true
		b.button_pressed = value == current
		b.pressed.connect(
			func() -> void:
				for other: Button in registry.values():
					other.button_pressed = false
				b.button_pressed = true
				on_pick.call(value)
				Sfx.click()
		)
		registry[value] = b
		row.add_child(b)
	return box


## Ri  track  P2 +18  /  NEXT  /  LOCKED — history entries are ordered by
## round (player_results appends per finished round), so index is the key.
func _schedule_row(
	index: int, track_id: String, weather_kind: String, history: Array, is_next: bool
) -> PanelContainer:
	var player := {}
	var done := index < history.size()
	if done:
		player = history[index]
	var edge := Color(1, 1, 1, 0.3)
	if done:
		edge = F1Theme.GREEN if int(player.get("position", 99)) <= 3 else F1Theme.PANEL_BG
	elif is_next:
		edge = F1Theme.RED
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", F1Theme.panel_style(F1Theme.PANEL_BG, edge))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)
	row.add_child(_cell("R%d" % (index + 1), 18, F1Theme.TEXT_DIM))
	row.add_child(_cell(_track_name(track_id), 18, Color.WHITE))
	var wet := WeatherState.wetness(weather_kind)
	(
		row
		. add_child(
			(
				UiIcons
				. icon(
					WeatherState.icon(weather_kind),
					15,
					Color(0.62, 0.72, 0.92) if wet > 0.0 else F1Theme.TEXT_DIM,
				)
			)
		)
	)
	var status := "LOCKED"
	var status_color := F1Theme.TEXT_DIM
	if done:
		status = "P%d  +%d PTS" % [int(player.get("position", 0)), int(player.get("points", 0))]
		status_color = F1Theme.YELLOW
	elif is_next:
		status = "NEXT"
		status_color = F1Theme.RED
	row.add_child(_cell(status, 18, status_color))
	return panel


## P1  K. VOSS   50 PTS   (player row gets the red edge).
func _standing_row(index: int, entry: Dictionary) -> PanelContainer:
	var name := str(entry.get("name", "?"))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		F1Theme.panel_style(
			F1Theme.RED if name == ChampionshipStore.PLAYER_NAME else F1Theme.PANEL_BG,
			F1Theme.RED if name == ChampionshipStore.PLAYER_NAME else Color(1, 1, 1, 0.3)
		)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	panel.add_child(row)
	row.add_child(_cell("P%d" % (index + 1), 19, Color.WHITE))
	row.add_child(_cell(name, 18, Color.WHITE))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_cell("%d W" % int(entry.get("wins", 0)), 16, F1Theme.TEXT_DIM))
	row.add_child(_cell("%d PTS" % int(entry.get("points", 0)), 19, F1Theme.YELLOW))
	return panel


func _cell(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("semibold"))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Track display name from the injected catalog; falls back to the raw id.
func _track_name(track_id: String) -> String:
	for entry in _catalog:
		if str(entry.get("id", "")) == track_id:
			return str(entry.get("name", track_id.to_upper()))
	return track_id.to_upper()
