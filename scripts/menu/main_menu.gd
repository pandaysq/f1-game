extends Control
## Main menu (0.4.0): F1-broadcast look — animated flowing backdrop, skewed
## red-accent buttons, settings screen, and disabled stubs for future modes
## (online multiplayer, championship, garage). The menu is the new entry
## scene; it switches into scenes/main.tscn with Settings.launch_mode.
##
## Dev hook: APEX_SHOT_DIR=<dir> saves a menu screenshot and quits (visual QA).

const MAIN_SCENE := "res://scenes/main.tscn"

var _shot_dir := ""
var _shot_wait := 0.0
var _settings_panel: SettingsPanel


func _ready() -> void:
	Settings.apply_quality()
	add_child(MenuBackground.new())

	_add_logo()
	_add_buttons()
	_add_footer()
	_settings_panel = SettingsPanel.new(func() -> void: pass)
	add_child(_settings_panel)
	# QA hook: capture the settings panel instead of the plain menu
	if OS.get_environment("APEX_SHOT_VIEW") == "settings":
		_settings_panel.visible = true
	if not OS.get_environment("APEX_SHOT_DIR").is_empty():
		_shot_dir = OS.get_environment("APEX_SHOT_DIR")


func _process(delta: float) -> void:
	if _shot_dir.is_empty():
		return
	_shot_wait += delta
	if _shot_wait >= 1.0:
		_shot_dir = ""  # guard: capture once
		var dir := OS.get_environment("APEX_SHOT_DIR")
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/menu_shot.png" % dir)
		print("menu screenshot saved: %s/menu_shot.png" % dir)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _settings_panel.visible:
		return  # handled by the settings panel itself
	if event.is_action_pressed("ui_accept") and not _settings_panel.visible:
		_start("race")


func _add_logo() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -320
	box.offset_right = 320
	box.offset_top = 64
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var strip := ColorRect.new()
	strip.color = F1Theme.RED
	strip.custom_minimum_size = Vector2(96, 10)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(strip)

	var title := Label.new()
	title.text = "APEX GP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", F1Theme.font("black"))
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F1-STYLE RACING  ///  SEASON ONE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", F1Theme.font("semibold"))
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	box.add_child(subtitle)


func _add_buttons() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -190
	box.offset_right = 190
	box.offset_top = -52
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var play := F1Theme.button("PLAY", 38, Vector2(380, 64))
	play.pressed.connect(func() -> void: _start("race"))
	box.add_child(play)

	var tt := F1Theme.button("TIME TRIAL", 28, Vector2(380, 56))
	tt.pressed.connect(func() -> void: _start("tt"))
	box.add_child(tt)

	var settings := F1Theme.button("SETTINGS", 28, Vector2(380, 56))
	settings.pressed.connect(func() -> void: _settings_panel.visible = true)
	box.add_child(settings)

	# future modes (phase 3+): visible stubs, disabled
	box.add_child(_stub_button("MULTIPLAYER  ///  ONLINE"))
	box.add_child(_stub_button("CHAMPIONSHIP"))
	box.add_child(_stub_button("GARAGE"))

	play.grab_focus()


func _stub_button(label: String) -> Button:
	var b := F1Theme.button(label, 22, Vector2(380, 46))
	b.disabled = true
	return b


func _add_footer() -> void:
	var version := Label.new()
	version.text = "APEX GP  v0.5.0"
	version.add_theme_font_override("font", F1Theme.font("bold"))
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 24
	version.offset_top = -40
	version.offset_bottom = -16
	add_child(version)

	var note := Label.new()
	note.text = "Fictional league game. Not affiliated with Formula 1."
	note.add_theme_font_override("font", F1Theme.font("regular"))
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	note.offset_left = -420
	note.offset_top = -38
	note.offset_bottom = -16
	note.offset_right = -24
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(note)


func _start(mode: String) -> void:
	Settings.launch_mode = mode
	get_tree().change_scene_to_file(MAIN_SCENE)
