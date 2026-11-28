class_name WeatherState
extends RefCounted
## Race weather (0.10.0): dry / light rain / heavy rain as a track wetness
## scalar 0..1. Pure logic — no scene, no autoload — so the setup screen, the
## championship calendar and the physics share one source of truth. Wetness
## is fixed per race for now (no drying line yet — KNOWN_ISSUES); the grip
## and wear effects of a compound live in TyreCompound, the rain / spray /
## wet-road visuals in main.gd and RainFx read the same kind.

const TYPES: Array[String] = ["dry", "light", "heavy"]
const DEFAULT_TYPE := "dry"

## Fixed track wetness per weather kind (fraction of full rain).
const WETNESS: Dictionary = {"dry": 0.0, "light": 0.45, "heavy": 0.85}

## Broadcast labels and icon names (UiIcons set).
const LABELS: Dictionary = {"dry": "DRY", "light": "LIGHT RAIN", "heavy": "HEAVY RAIN"}
const ICONS: Dictionary = {"dry": "sun", "light": "drizzle", "heavy": "rain"}


## True when the kind is one of the setup-screen choices.
static func is_valid(kind: String) -> bool:
	return TYPES.has(kind)


## Normalizes any stored value (old settings files, JSON) to a valid kind.
static func sanitize(kind: String) -> String:
	return kind if is_valid(kind) else DEFAULT_TYPE


## Track wetness 0..1 for the kind.
static func wetness(kind: String) -> float:
	return float(WETNESS.get(sanitize(kind), 0.0))


## Broadcast label ("LIGHT RAIN").
static func label(kind: String) -> String:
	return str(LABELS.get(sanitize(kind), "DRY"))


## Icon name for the kind ("drizzle").
static func icon(kind: String) -> String:
	return str(ICONS.get(sanitize(kind), "sun"))


## Deterministic weather for a championship season: seeded by the season key,
## so the same season always shows the same calendar. Rolls: dry 55% /
## light 30% / heavy 15%.
static func season_calendar(season_key: String, rounds: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(season_key)
	var out: Array[String] = []
	for i in range(maxi(rounds, 1)):
		var roll := rng.randf()
		if roll < 0.55:
			out.append("dry")
		elif roll < 0.85:
			out.append("light")
		else:
			out.append("heavy")
	return out
