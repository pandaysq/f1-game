class_name DriverRoster
extends RefCounted
## Broadcast-style driver identity per grid slot (0.9.0). Every AI races
## under a fictional name and a 3-letter tag instead of "AI1"-style labels.
## Names reuse ChampionshipStore.AI_NAMES, so plain races and championship
## seasons show the same roster; tags and tower bar colors live here.
## Slot 0 is always the player (red bar, YOU). No real-world drivers —
## master prompt rule.

const PLAYER_TAG := "YOU"

## 3-letter broadcast tags, order matches ChampionshipStore.AI_NAMES.
const TAGS: Array[String] = ["VOS", "MAR", "OKO", "SIL", "TAN", "ILE", "DUB"]

## Tower bar colors (team-style accents, readable on the dark panels).
const TOWER_COLORS: Array[Color] = [
	Color(0.0, 0.82, 0.75),  # teal
	Color(1.0, 0.5, 0.0),  # orange
	Color(0.27, 0.52, 0.96),  # blue
	Color(0.68, 0.15, 1.0),  # purple
	Color(1.0, 0.41, 0.71),  # pink
	Color(0.64, 0.87, 0.28),  # lime
	Color(0.82, 0.84, 0.9),  # silver
]

## Safety net for out-of-grid slots (was the only naming before 0.9.0).
const FALLBACK_PREFIX := "AI"


## Full name for results and tables: season roster wins when provided
## (index 0 is the player, slot i maps to names[i]), else the base roster
## (AI_NAMES holds the 7 AI only, so slot i maps to AI_NAMES[i - 1]).
static func display_name(car_index: int, season_names: Array = []) -> String:
	if car_index == 0:
		return ChampionshipStore.PLAYER_NAME
	if not season_names.is_empty():
		if car_index < season_names.size():
			return str(season_names[car_index])
	elif car_index - 1 < ChampionshipStore.AI_NAMES.size():
		return ChampionshipStore.AI_NAMES[car_index - 1]
	return "%s%d" % [FALLBACK_PREFIX, car_index]


## 3-letter tag for tower rows ("VOS"); player is YOU.
static func tag(car_index: int, season_names: Array = []) -> String:
	if car_index == 0:
		return PLAYER_TAG
	var idx := car_index - 1
	if idx >= 0 and idx < TAGS.size():
		return TAGS[idx]
	return display_name(car_index, season_names).substr(0, 3)


## Bar color of the timing tower / result rows; player is F1 red.
static func tower_color(car_index: int) -> Color:
	if car_index == 0:
		return F1Theme.RED
	var idx := car_index - 1
	if idx >= 0 and idx < TOWER_COLORS.size():
		return TOWER_COLORS[idx]
	return Color(1, 1, 1, 0.4)
