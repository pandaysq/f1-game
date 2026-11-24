class_name SettingsPanel
extends Control
## Settings screen (0.4.0): driver assists toggles + graphics quality,
## persisted via Settings.save_settings(). F1-broadcast look: dark skewed
## panels, red accents, Titillium.

var _on_changed: Callable
var _quality_buttons: Array[Button] = []


func _init(on_changed: Callable) -> void:
	_on_changed = on_changed
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.88)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_override("font", F1Theme.font("black"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", F1Theme.RED)
	box.add_child(title)

	box.add_child(_section("DRIVER ASSISTS"))
	for key in Settings.assists:
		box.add_child(_assist_row(key))
	box.add_child(_spacer(4))
	box.add_child(_section("GRAPHICS QUALITY"))
	box.add_child(_quality_row())

	box.add_child(_spacer(8))
	var back := F1Theme.button("BACK  [ESC]", 24, Vector2(220, 44))
	back.pressed.connect(hide)
	box.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


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


func _assist_row(key: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var row_style := F1Theme.panel_style()
	row_style.content_margin_top = 4.0
	row_style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)

	var title := _row_title(key)
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var check := CheckButton.new()
	check.button_pressed = bool(Settings.assists[key])
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(
		func(on: bool) -> void:
			Settings.assists[key] = on
			Settings.save_settings()
			if _on_changed.is_valid():
				_on_changed.call()
	)
	row.add_child(check)
	return panel


## "auto_gearbox" -> "AUTO GEARBOX".
func _row_title(key: String) -> Label:
	var l := Label.new()
	l.text = String(key).to_upper().replace("_", " ")
	l.add_theme_font_override("font", F1Theme.font("semibold"))
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _quality_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for preset in ["low", "medium", "high"]:
		var b := F1Theme.button(preset.to_upper(), 22, Vector2(160, 50))
		b.toggle_mode = true
		b.button_pressed = Settings.quality == preset
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _pick_quality(preset))
		_quality_buttons.append(b)
		row.add_child(b)
	return row


func _pick_quality(preset: String) -> void:
	Settings.quality = preset
	Settings.save_settings()
	Settings.apply_quality()
	for i in range(_quality_buttons.size()):
		_quality_buttons[i].button_pressed = _quality_buttons[i].text == preset.to_upper()
	if _on_changed.is_valid():
		_on_changed.call()
