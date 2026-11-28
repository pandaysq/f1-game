class_name UiIcons
extends RefCounted
## HUD/menu icon set (0.9.0): white single-path SVGs in assets/ui/icons.
## Sources: game-icons.net (CC BY 3.0, see ASSETS.md) plus a hand-made
## track-limits flag. One white source per glyph, tinted through modulate,
## so every state color comes free. Cached textures, TextureRect factory.

const DIR := "res://assets/ui/icons/"

## Names shipped with the project (asset table mirrors this list).
const NAMES: Array[String] = [
	"car-wheel",
	"checkered-flag",
	"crown",
	"flag",
	"flat-tire",
	"gears",
	"podium-winner",
	"steering-wheel",
	"stopwatch",
	"trophy",
	"world",
]

static var _cache: Dictionary = {}


## Tintable texture by name ("stopwatch"); null when the name is unknown.
static func texture(name: String) -> Texture2D:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".svg")
	return _cache[name]


## Icon control sized for containers (containers drive layout, the rect
## only scales the texture). size in design pixels at 1280x720.
static func icon(name: String, size: float, color: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture(name)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect
