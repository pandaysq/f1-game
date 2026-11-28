class_name TyreCompound
extends RefCounted
## Tyre compounds for wet weather (0.10.0): slick / intermediate / wet.
## Grip and wear ratings are lerped between a dry and a wet value by the
## track wetness (WeatherState), so dry + slick is exactly the pre-weather
## physics — the multiplier is 1.0 and nothing moves. Ratings can be tuned
## from vehicle.json (tires.compounds) without touching code. The AI picks
## the best compound for the conditions via best_for_wetness().

const COMPOUNDS: Array[String] = ["slick", "inter", "wet"]
const DEFAULT_COMPOUND := "slick"

## Code defaults; vehicle.json tires.compounds may override any rating.
## grip_* multiplies the tire friction, wear_* multiplies the wear rate.
const DEFAULTS: Dictionary = {
	"slick": {"grip_dry": 1.0, "grip_wet": 0.72, "wear_dry": 1.0, "wear_wet": 1.0},
	"inter": {"grip_dry": 0.93, "grip_wet": 0.96, "wear_dry": 1.3, "wear_wet": 1.0},
	"wet": {"grip_dry": 0.84, "grip_wet": 1.0, "wear_dry": 1.8, "wear_wet": 0.9},
}

## Chip colors in broadcast tyre-assignment style (red slick, green
## intermediate, blue wet).
const COLORS: Dictionary = {
	"slick": Color(0.9, 0.16, 0.12),
	"inter": Color(0.1, 0.85, 0.3),
	"wet": Color(0.2, 0.55, 1.0),
}

## Single-letter chip for the HUD ("S", "I", "W").
const LETTERS: Dictionary = {"slick": "S", "inter": "I", "wet": "W"}

## Setup-screen labels ("INTER").
const LABELS: Dictionary = {"slick": "SLICK", "inter": "INTER", "wet": "WET"}


## True when the compound is one of the setup-screen choices.
static func is_valid(compound: String) -> bool:
	return COMPOUNDS.has(compound)


## Normalizes any stored value (old settings files, JSON) to a valid compound.
static func sanitize(compound: String) -> String:
	return compound if is_valid(compound) else DEFAULT_COMPOUND


## Merged ratings (code defaults + optional vehicle.json overrides).
static func _ratings(compound: String, tires: Dictionary) -> Dictionary:
	var base: Dictionary = DEFAULTS.get(sanitize(compound), DEFAULTS[DEFAULT_COMPOUND])
	var out := {}
	for key in base:
		out[key] = base[key]
	var json: Variant = tires.get("compounds", {}).get(sanitize(compound), {})
	if json is Dictionary:
		for key in json:
			out[key] = float(json[key])
	return out


## Friction multiplier for the compound at the track wetness 0..1. Dry track
## plus slick returns exactly 1.0 (physics unchanged from 0.9.0).
static func grip(compound: String, wetness: float, tires: Dictionary = {}) -> float:
	var r := _ratings(compound, tires)
	var wet := clampf(wetness, 0.0, 1.0)
	return lerpf(float(r["grip_dry"]), float(r["grip_wet"]), wet)


## Wear-rate multiplier for the compound at the track wetness 0..1 (wets
## overheat on a dry track, slicks live longer than anyone in the rain).
static func wear_mult(compound: String, wetness: float, tires: Dictionary = {}) -> float:
	var r := _ratings(compound, tires)
	var wet := clampf(wetness, 0.0, 1.0)
	return lerpf(float(r["wear_dry"]), float(r["wear_wet"]), wet)


## The compound with the most grip in the given conditions — the AI's
## automatic choice. Ties keep the earlier (faster-wearing) compound out.
static func best_for_wetness(wetness: float, tires: Dictionary = {}) -> String:
	var best := DEFAULT_COMPOUND
	var best_grip := -INF
	for compound in COMPOUNDS:
		var g := grip(compound, wetness, tires)
		if g > best_grip:
			best_grip = g
			best = compound
	return best


## Single-letter HUD chip ("S").
static func letter(compound: String) -> String:
	return str(LETTERS.get(sanitize(compound), "S"))


## Chip color for the compound.
static func color(compound: String) -> Color:
	return COLORS.get(sanitize(compound), COLORS[DEFAULT_COMPOUND])


## Setup-screen label ("INTER").
static func label(compound: String) -> String:
	return str(LABELS.get(sanitize(compound), "SLICK"))
