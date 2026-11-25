class_name PauseMenu
extends CanvasLayer
## Pause overlay (0.4.0, extended 0.6.0): Esc / P / touch pause button.
## Pauses the whole tree; offers resume, race restart, quick audio settings
## (volumes + haptics, same rows as the main settings screen) and exit to
## the main menu. Runs with PROCESS_MODE_ALWAYS so it keeps working while
## the tree is paused.

var _root: Control
var _quick_settings: VBoxContainer
var _buttons_box: VBoxContainer


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", F1Theme.font("black"))
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", F1Theme.RED)
	box.add_child(title)

	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 14)
	box.add_child(_buttons_box)

	var resume := F1Theme.button("RESUME", 32)
	resume.pressed.connect(_close)
	_buttons_box.add_child(resume)

	var restart := F1Theme.button("RESTART", 32)
	restart.pressed.connect(_restart)
	_buttons_box.add_child(restart)

	var quick := F1Theme.button("QUICK SETTINGS", 32)
	quick.pressed.connect(_toggle_quick)
	_buttons_box.add_child(quick)

	var exit := F1Theme.button("EXIT TO MENU", 32)
	exit.pressed.connect(_exit_to_menu)
	_buttons_box.add_child(exit)

	_quick_settings = VBoxContainer.new()
	_quick_settings.add_theme_constant_override("separation", 8)
	_quick_settings.visible = false
	box.add_child(_quick_settings)
	var audio_label := Label.new()
	audio_label.text = "AUDIO  ///  HAPTICS"
	audio_label.add_theme_font_override("font", F1Theme.font("bold"))
	audio_label.add_theme_font_size_override("font_size", 16)
	audio_label.add_theme_color_override("font_color", F1Theme.TEXT_DIM)
	audio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_settings.add_child(audio_label)
	for key in ["master", "music", "sfx"]:
		_quick_settings.add_child(F1Theme.volume_row(key, 340))
	_quick_settings.add_child(F1Theme.vibration_row())

	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		if _quick_settings.visible:
			_quick_settings.visible = false
			_buttons_box.visible = true
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if get_tree().paused:
		_close()
	else:
		_open()


func _open() -> void:
	get_tree().paused = true
	_quick_settings.visible = false
	_buttons_box.visible = true
	_root.visible = true
	visible = true
	Sfx.open()


func _close() -> void:
	get_tree().paused = false
	_root.visible = false
	visible = false
	Sfx.close()


func _toggle_quick() -> void:
	if _quick_settings.visible:
		Sfx.close()
	else:
		Sfx.open()
	_quick_settings.visible = not _quick_settings.visible
	_buttons_box.visible = not _quick_settings.visible


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _exit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
