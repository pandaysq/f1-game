class_name F1Theme
extends RefCounted
## F1 broadcast-style UI theme (0.4.0, icon/divider system 0.9.0): colors,
## fonts and factories for the skewed dark panels with red edges seen on F1
## TV graphics. Titillium Web is the closest free face to the official F1
## Display font (SIL OFL 1.1). Text separators ("///" era) are gone: rows
## compose through sep() slabs, icons and spacing instead.

const RED := Color(0.882353, 0.023529, 0.0)  # #e10600 F1 red
const DARK := Color(0.082353, 0.082353, 0.117647)  # #15151e F1 dark
const PANEL_BG := Color(0.07, 0.07, 0.11, 0.86)
const GREEN := Color(0.0, 0.823529, 0.745098)  # #00d2be teal accent
const PURPLE := Color(0.682353, 0.152941, 1.0)  # fastest-lap purple
const YELLOW := Color(1.0, 0.8, 0.2)
const TEXT_DIM := Color(1, 1, 1, 0.75)

const FONT_FILES := {
	"black": "TitilliumWeb-Black.ttf",
	"bold": "TitilliumWeb-Bold.ttf",
	"semibold": "TitilliumWeb-SemiBold.ttf",
	"regular": "TitilliumWeb-Regular.ttf",
}

static var _font_cache: Dictionary = {}


## kind: "black" | "bold" | "semibold" | "regular".
static func font(kind: String = "black") -> FontFile:
	if not _font_cache.has(kind):
		var path := "res://assets/ui/fonts/%s" % FONT_FILES.get(kind, FONT_FILES["black"])
		_font_cache[kind] = load(path)
	return _font_cache[kind]


## Dark skewed panel with a colored left edge — the F1 TV "tower" look.
static func panel_style(bg: Color = PANEL_BG, edge: Color = RED) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 6
	sb.border_color = edge
	sb.skew = Vector2(-0.35, 0)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


## F1-style menu button: skewed dark slab, red left edge; hover = red fill.
## Every button clicks (Sfx) — one hook covers menu, settings and pause.
static func button(
	text: String, font_size: int = 32, min_size: Vector2 = Vector2(380, 62)
) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font("black"))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.28))
	b.add_theme_stylebox_override("normal", panel_style())
	b.add_theme_stylebox_override("focus", panel_style(Color(0.12, 0.12, 0.17, 0.9)))

	var hover := panel_style(RED, RED)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := panel_style(RED.darkened(0.3), RED)
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := panel_style(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.22))
	b.add_theme_stylebox_override("disabled", disabled)
	b.pressed.connect(_click)
	return b


## Click feedback for every themed button. Sfx is resolved through the scene
## tree at press time: the theme stays free of autoload identifiers, so
## --script startup compiles it cleanly (headless checks never press).
static func _click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not tree.root.has_node("Sfx"):
		return
	tree.root.get_node("Sfx").click()


## Small skewed color slab — the row divider of F1 TV graphics. Compose
## [text][sep][text] rows with it instead of string separators.
static func sep(color: Color = RED, height: float = 20.0) -> Control:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.skew = Vector2(-0.35, 0)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(11.0, height)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return panel


## Text width under a theme font, plus padding — picks uniform chip widths
## so every button of a choice row fits its label ("ROOKIE" beat 86 px).
static func fit_width(
	texts: Array, font_size: int, min_width: float, padding: float = 46.0
) -> float:
	var widest := 0.0
	var f := font("black")
	for t: String in texts:
		widest = maxf(widest, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return maxf(min_width, ceilf(widest + padding))


## One-line heading row: [icon] LABEL — icon optional, caller adds more
## children (sep, sub-labels) to the returned box when needed.
static func heading(
	text: String, font_size: int = 32, color: Color = RED, icon_name: String = ""
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	if not icon_name.is_empty():
		row.add_child(UiIcons.icon(icon_name, font_size * 0.9, Color.WHITE))
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font("black"))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	row.add_child(l)
	return row


## Compact skewed stat chip: dark panel, centered label. Used for the
## season-info strip and similar short facts.
static func chip(
	text: String, font_size: int = 15, color: Color = TEXT_DIM, edge: Color = Color(1, 1, 1, 0.25)
) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := panel_style(PANEL_BG, edge)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font("semibold"))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	panel.add_child(l)
	return panel


## BACK button plus a dim ESC key hint, centered as one row. Panels wire
## their close logic through on_close (Sfx already rides the button).
static func back_row(
	on_close: Callable, font_size: int = 24, min_size: Vector2 = Vector2(220, 44)
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := button("BACK", font_size, min_size)
	b.pressed.connect(on_close)
	row.add_child(b)
	var hint := Label.new()
	hint.text = "ESC"
	hint.add_theme_font_override("font", font("bold"))
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	return row


## Disabled future-mode button: icon + dim label, SOON tag pinned right.
static func stub_button(label: String, icon_name: String, font_size: int = 22) -> Button:
	var b := button(label, font_size, Vector2(380, 42))
	b.disabled = true
	b.icon = UiIcons.texture(icon_name)
	b.add_theme_constant_override("icon_max_width", 20)
	b.focus_mode = Control.FOCUS_NONE
	var overlay := HBoxContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.offset_right = -18.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(overlay)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.add_child(spacer)
	var soon := tag("SOON")
	soon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	overlay.add_child(soon)
	return b


## Small right-aligned tag ("SOON") used on disabled future buttons.
static func tag(text: String, color: Color = YELLOW) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font("bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	return l


## Autoload-free Settings/Sfx access for theme factories: resolved through
## the scene tree at call time, so --script startup compiles this file
## without the autoload singletons (headless checks never drag sliders).
static func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(name)


## Volume slider row wired to Settings.volumes (0.6.0). Used by the main
## settings screen and the pause menu alike. Saves + reroutes buses on drag end.
static func volume_row(key: String, slider_width: int = 360) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := Label.new()
	l.text = key.to_upper()
	l.add_theme_font_override("font", font("semibold"))
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 1.0
	var settings := _autoload("Settings")
	if settings != null:
		slider.value = clampf(float(settings.volumes.get(key, 1.0)), 0.0, 1.0)
	slider.custom_minimum_size = Vector2(slider_width, 36)
	slider.focus_mode = Control.FOCUS_NONE
	slider.drag_ended.connect(
		func(changed: bool) -> void:
			if not changed:
				return
			var store := _autoload("Settings")
			if store == null:
				return
			store.volumes[key] = slider.value
			store.save_settings()
			store.apply_volumes()
			var sfx := _autoload("Sfx")
			if sfx != null:
				sfx.toggle()
	)
	row.add_child(slider)
	return row


## Haptics toggle row wired to Settings.vibration (0.6.0).
static func vibration_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := Label.new()
	l.text = "VIBRATION"
	l.add_theme_font_override("font", font("semibold"))
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var check := CheckButton.new()
	var settings := _autoload("Settings")
	if settings != null:
		check.button_pressed = bool(settings.vibration)
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(
		func(on: bool) -> void:
			var sfx := _autoload("Sfx")
			if sfx != null:
				sfx.toggle()
			var store := _autoload("Settings")
			if store == null:
				return
			store.vibration = on
			store.save_settings()
	)
	row.add_child(check)
	return row
