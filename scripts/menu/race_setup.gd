class_name RaceSetupPanel
extends Control
## Pre-race setup screen (0.6.0): track choice (Settings.TRACKS), lap count
## and AI difficulty. Selections persist via Settings.race. The START button
## launches scenes/main.tscn with the launch mode chosen in the menu
## ("race" shows laps + difficulty, "tt" hides them).

var _mode: String
var _track_buttons: Dictionary = {}
var _lap_buttons: Dictionary = {}
var _level_buttons: Dictionary = {}


func _init(launch_mode: String) -> void:
	_mode = launch_mode
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
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "RACE SETUP" if _mode == "race" else "TIME TRIAL"
	title.add_theme_font_override("font", F1Theme.font("black"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", F1Theme.RED)
	box.add_child(title)

	var track_ids: Array = []
	for t in Settings.TRACKS:
		track_ids.append(str(t.get("id", "")))
	box.add_child(_section("TRACK"))
	box.add_child(
		_choice_row(
			track_ids,
			_track_buttons,
			_pick_track,
			str(Settings.race.get("track", Settings.DEFAULT_TRACK))
		)
	)

	if _mode == "race":
		var laps: Array = []
		for v in Settings.LAP_CHOICES:
			laps.append(str(v))
		box.add_child(
			_section_block(
				"LAPS", laps, _lap_buttons, _pick_laps, str(int(Settings.race.get("laps", 5))), 96.0
			)
		)
		box.add_child(
			_section_block(
				"AI DIFFICULTY",
				Settings.AI_LEVELS,
				_level_buttons,
				_pick_level,
				str(Settings.race.get("difficulty", "pro")),
				130.0
			)
		)

	box.add_child(_spacer(8))
	var start_label := "START RACE" if _mode == "race" else "START TIME TRIAL"
	var start := F1Theme.button(start_label, 30, Vector2(380, 60))
	start.pressed.connect(_launch)
	box.add_child(start)
	box.add_child(F1Theme.back_row(_close, 24, Vector2(380, 44)))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	Sfx.back()
	hide()


func _launch() -> void:
	Settings.launch_mode = _mode
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F1Theme.font("bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	return l


func _section_block(
	title_text: String,
	options: Array,
	store: Dictionary,
	pick: Callable,
	current: String,
	min_width: float = 220.0
) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section(title_text))
	box.add_child(_choice_row(options, store, pick, current, min_width))
	return box


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Row of toggle buttons; picking one re-presses it and un-presses the rest.
## Uniform width fits the widest label so no text ever clips (0.9.0).
func _choice_row(
	options: Array, store: Dictionary, pick: Callable, current: String, min_width: float = 220.0
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var labels: Array = []
	for option in options:
		labels.append(String(option).to_upper().replace("_", " "))
	var width := F1Theme.fit_width(labels, 22, min_width)
	for i in range(options.size()):
		var option: Variant = options[i]
		var label: String = labels[i]
		var b := F1Theme.button(label, 22, Vector2(width, 50))
		b.toggle_mode = true
		b.button_pressed = String(option) == current
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: pick.call(option))
		store[option] = b
		row.add_child(b)
	return row


func _sync_buttons(store: Dictionary, chosen: String) -> void:
	for option in store:
		var b: Button = store[option]
		b.button_pressed = String(option) == chosen


func _pick_track(track_id: String) -> void:
	Sfx.select()
	Settings.race["track"] = track_id
	Settings.save_settings()
	_sync_buttons(_track_buttons, track_id)


func _pick_laps(laps_text: String) -> void:
	Sfx.select()
	Settings.race["laps"] = int(laps_text)
	Settings.save_settings()
	_sync_buttons(_lap_buttons, laps_text)


func _pick_level(level: String) -> void:
	Sfx.select()
	Settings.race["difficulty"] = level
	Settings.save_settings()
	_sync_buttons(_level_buttons, level)
