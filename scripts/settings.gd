extends Node
## Global settings autoload (Phase 0; persistence 0.4.0; audio/race 0.6.0).
##
## Stores assist toggles, quality preset, audio volumes, per-session race
## parameters (track, laps, AI difficulty) and haptic feedback. Gameplay code
## must read from here, never from hardcoded values, so league rules and the
## setup screen can override per session.
## Saved to user://settings.cfg from the settings screens.

const SAVE_PATH := "user://settings.cfg"

## Tracks selectable in the race setup screen (0.6.0). The diorama environment
## is authored for endurance_run only; other tracks run on the generated
## scenery. APEX_TRACK env overrides the choice for headless/test runs.
const TRACKS := [
	{"id": "endurance_run", "name": "ENDURANCE RUN", "path": "res://tracks/endurance_run.json"},
	{"id": "alpha_loop", "name": "ALPHA LOOP", "path": "res://tracks/alpha_loop.json"},
]
const DEFAULT_TRACK := "endurance_run"

## Lap-count choices and AI levels offered by the setup screen.
const LAP_CHOICES := [3, 5, 8]
const AI_LEVELS := ["rookie", "pro", "legend"]

## Assist flags. All individual toggles per master prompt section 4.
## Defaults chosen for a new player: forgiving but honest physics.
var assists: Dictionary = {
	"auto_gearbox": true,
	"steering_assist": true,
	"stability_control": true,
	"abs": true,
	"traction_control": true,
	"racing_line": false,
}

## Quality preset ("low" / "medium" / "high"): MSAA + 3D resolution scale.
var quality: String = "medium"

## Audio volumes, linear 0..1, routed through the Master / Music / SFX buses.
var volumes: Dictionary = {"master": 0.85, "music": 0.55, "sfx": 1.0}

## Race setup selections (0.6.0): track id, lap count, AI difficulty level.
var race: Dictionary = {"track": DEFAULT_TRACK, "laps": 5, "difficulty": "pro"}

## Haptic feedback on touch devices (crash, nitro pulse, green flag).
var vibration: bool = true

## Launch mode chosen in the main menu ("race" | "tt"). The main scene reads
## it; APEX_MODE env still wins for headless/test runs.
var launch_mode: String = "race"


func _ready() -> void:
	load_settings()
	apply_quality()
	apply_volumes()
	print(
		(
			"[Settings] ready, assists=%s quality=%s race=%s volumes=%s"
			% [str(assists.keys()), quality, str(race), str(volumes)]
		)
	)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for key in assists:
		cf.set_value("assists", key, assists[key])
	cf.set_value("graphics", "quality", quality)
	for key in volumes:
		cf.set_value("audio", key, volumes[key])
	for key in race:
		cf.set_value("race", key, race[key])
	cf.set_value("game", "vibration", vibration)
	var err := cf.save(SAVE_PATH)
	if err != OK:
		push_warning("[Settings] cannot save: %s" % error_string(err))


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for key in assists:
		assists[key] = bool(cf.get_value("assists", key, assists[key]))
	quality = str(cf.get_value("graphics", "quality", quality))
	for key in volumes:
		var v := float(cf.get_value("audio", key, volumes[key]))
		volumes[key] = clampf(v, 0.0, 1.0)
	for key in race:
		race[key] = cf.get_value("race", key, race[key])
	if track_path(str(race.get("track", ""))).is_empty():
		race["track"] = DEFAULT_TRACK
	if not (int(race.get("laps", 5)) in LAP_CHOICES):
		race["laps"] = 5
	if not (str(race.get("difficulty", "pro")) in AI_LEVELS):
		race["difficulty"] = "pro"
	vibration = bool(cf.get_value("game", "vibration", vibration))


## Applies the quality preset to the root viewport (MSAA + resolution scale).
## Safe to call in menus (no 3D yet) and headless (no SceneTree).
func apply_quality() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var viewport: Viewport = (loop as SceneTree).root
	if viewport == null:
		return
	match quality:
		"low":
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.scaling_3d_scale = 0.75
		"high":
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.scaling_3d_scale = 1.0
		_:
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.scaling_3d_scale = 1.0


# ------------------------------------------------------------ audio buses


## Creates the Music and SFX buses (idempotent) and applies saved volumes.
## Buses let the menu music duck independently from the SFX stage.
func apply_volumes() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for key in volumes:
		var bus := _bus_for(key)
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var linear := float(volumes[key])
		AudioServer.set_bus_mute(idx, linear <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


## "master" -> "Master", "music" -> "Music", "sfx" -> "SFX".
func _bus_for(key: String) -> String:
	match key:
		"master":
			return "Master"
		"music":
			return "Music"
		"sfx":
			return "SFX"
	return ""


# ------------------------------------------------------------ track registry


## Track file path by id; empty string when unknown. Keeps old saved cfgs
## pointing at a missing track from breaking the main scene.
func track_path(track_id: String) -> String:
	for t in TRACKS:
		if str(t.get("id", "")) == track_id:
			return str(t.get("path", ""))
	return ""


## Display name by id (fallback: upper-cased id).
func track_name(track_id: String) -> String:
	for t in TRACKS:
		if str(t.get("id", "")) == track_id:
			return str(t.get("name", ""))
	return track_id.to_upper()
