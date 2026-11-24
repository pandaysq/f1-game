class_name PauseMenu
extends CanvasLayer
## Pause overlay (0.4.0): Esc / P / touch pause button. Pauses the whole
## tree; offers resume, race restart and exit to the main menu. Runs with
## PROCESS_MODE_ALWAYS so it keeps working while the tree is paused.

var _root: Control


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

	var resume := F1Theme.button("RESUME", 32)
	resume.pressed.connect(_close)
	box.add_child(resume)

	var restart := F1Theme.button("RESTART RACE", 32)
	restart.pressed.connect(_restart)
	box.add_child(restart)

	var exit := F1Theme.button("EXIT TO MENU", 32)
	exit.pressed.connect(_exit_to_menu)
	box.add_child(exit)

	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if get_tree().paused:
		_close()
	else:
		_open()


func _open() -> void:
	get_tree().paused = true
	_root.visible = true
	visible = true


func _close() -> void:
	get_tree().paused = false
	_root.visible = false
	visible = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _exit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
