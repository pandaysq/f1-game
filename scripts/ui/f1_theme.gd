class_name F1Theme
extends RefCounted
## F1 broadcast-style UI theme (0.4.0): colors, fonts and factories for the
## skewed dark panels with red edges seen on F1 TV graphics. Titillium Web is
## the closest free face to the official F1 Display font (SIL OFL 1.1).

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
	b.pressed.connect(func() -> void: Sfx.click())
	return b


## Small right-aligned tag ("SOON") used on disabled future buttons.
static func tag(text: String, color: Color = YELLOW) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font("bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	return l
