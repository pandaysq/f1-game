extends Node
## Global settings autoload (Phase 0, persistence added in 0.4.0).
##
## Stores assist toggles and the quality preset. Gameplay code must read
## assists from here, never from hardcoded values, so league rules (Phase 7)
## and the setup screen (Phase 8) can override them per session.
## Saved to user://settings.cfg from the settings screen.

const SAVE_PATH := "user://settings.cfg"

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

## Launch mode chosen in the main menu ("race" | "tt"). The main scene reads
## it; APEX_MODE env still wins for headless/test runs.
var launch_mode: String = "race"


func _ready() -> void:
	load_settings()
	apply_quality()
	print("[Settings] ready, assists=%s quality=%s" % [str(assists.keys()), quality])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for key in assists:
		cf.set_value("assists", key, assists[key])
	cf.set_value("graphics", "quality", quality)
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
