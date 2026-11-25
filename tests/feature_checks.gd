class_name FeatureChecks
extends RefCounted
## Feature checks for 0.6.0 (race setup, volumes/buses, track limits, ghost,
## career-lite, minimap, nitro fx, cockpit wheel, vibration, menu music).
## Call FeatureChecks.run(check, root).
##
## NOTE: --script runs do not instantiate autoloads, so autoload identifiers
## (Settings / Sfx) must never appear here. Scripts are load()ed at runtime
## and used through their own instances / statics / constant maps instead.

const MENU_LOOP := "res://assets/audio/music/menu_loop.ogg"


static func run(check: Callable, root: Node) -> void:
	print("[features]")
	var settings_script: GDScript = load("res://scripts/settings.gd")
	var settings: Node = settings_script.new()
	_test_track_registry(check, settings, settings_script)
	_test_audio_settings(check, settings)
	_test_menu_music(check)
	_test_track_limits(check)
	_test_ghost_pipeline(check, root)
	_test_career_store(check)
	_test_hud_widgets(check, root)
	_test_input_feedback(check)
	settings.free()


# ------------------------------------------------------------ settings


static func _test_track_registry(
	check: Callable, settings: Node, settings_script: GDScript
) -> void:
	check.call(settings.track_path("endurance_run") != "", "track registry maps endurance_run")
	check.call(settings.track_path("alpha_loop") != "", "track registry maps alpha_loop")
	check.call(settings.track_path("nope") == "", "unknown track id maps to empty path")
	check.call(settings.track_name("alpha_loop") == "ALPHA LOOP", "track display name lookup")
	check.call(settings.track_name("custom") == "CUSTOM", "unknown track name falls back to id")
	var laps: Array = settings_script.get_script_constant_map().get("LAP_CHOICES", [])
	var levels: Array = settings_script.get_script_constant_map().get("AI_LEVELS", [])
	check.call(
		laps.has(int(settings.race.get("laps", 5))), "saved race lap count is a legal choice"
	)
	check.call(
		levels.has(str(settings.race.get("difficulty", "pro"))),
		"saved AI difficulty is a legal level"
	)


static func _test_audio_settings(check: Callable, settings: Node) -> void:
	settings.apply_volumes()
	check.call(AudioServer.get_bus_index("Music") >= 0, "Music bus exists")
	check.call(AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists")
	var music_idx := AudioServer.get_bus_index("Music")
	var saved := float(settings.volumes.get("music", 0.55))
	settings.volumes["music"] = 0.0
	settings.apply_volumes()
	check.call(AudioServer.is_bus_mute(music_idx), "music volume 0 mutes the bus")
	settings.volumes["music"] = saved
	settings.apply_volumes()
	check.call(not AudioServer.is_bus_mute(music_idx), "music volume restored unmutes the bus")
	# round-trip through the save file
	var sfx_saved := float(settings.volumes.get("sfx", 1.0))
	settings.volumes["sfx"] = 0.42
	settings.save_settings()
	settings.volumes["sfx"] = 1.0
	settings.load_settings()
	check.call(
		absf(float(settings.volumes.get("sfx", 0.0)) - 0.42) < 0.001,
		"volume round-trips through settings.cfg"
	)
	settings.volumes["sfx"] = sfx_saved
	settings.save_settings()


# ------------------------------------------------------------ menu music


static func _test_menu_music(check: Callable) -> void:
	var stream := load(MENU_LOOP) as AudioStreamOggVorbis
	check.call(stream != null, "menu music loop loads")
	if stream != null:
		stream.loop = true
		check.call(stream.loop, "menu music loop flag is settable")
	check.call(load("res://scripts/audio/menu_music.gd") != null, "menu_music.gd compiles")


# ------------------------------------------------------------ track limits


static func _test_track_limits(check: Callable) -> void:
	var limits := TrackLimits.new()
	var invalidated_fired := [false]
	limits.lap_invalidated.connect(func(_c: int) -> void: invalidated_fired[0] = true)
	var cut_fired := [0]
	limits.cut_committed.connect(func(c: int) -> void: cut_fired[0] = c)
	# one sustained excursion = one cut
	limits.update(true, 40.0, 0.9)
	check.call(limits.cuts_this_lap == 0, "0.9 s off track does not count yet")
	limits.update(true, 40.0, 0.3)
	check.call(limits.cuts_this_lap == 1 and cut_fired[0] == 1, "sustained excursion counts a cut")
	# back on road: accumulation resets
	limits.update(false, 40.0, 0.5)
	limits.update(true, 40.0, 0.9)
	check.call(limits.cuts_this_lap == 1, "brief kerb hop does not count")
	# slow speed does not count
	limits.update(true, 3.0, 5.0)
	check.call(limits.cuts_this_lap == 1, "off track at crawl speed does not count")
	# two more full excursions -> invalidation (each cut needs 1 s sustained)
	limits.update(true, 40.0, 1.1)
	limits.update(false, 40.0, 0.2)
	limits.update(true, 40.0, 1.1)
	check.call(limits.cuts_this_lap == TrackLimits.LIMITS_PER_LAP, "three cuts accumulate")
	check.call(invalidated_fired[0], "third cut fires lap_invalidated")
	check.call(not limits.lap_valid(), "lap marked invalid after three cuts")
	limits.reset_lap()
	check.call(limits.lap_valid(), "lap crossing restores validity")


# ------------------------------------------------------------ ghost


static func _test_ghost_pipeline(check: Callable, root: Node) -> void:
	var recorder := GhostRecorder.new()
	recorder.start_lap()
	for i in range(30):  # 30 ticks * 1/60 s = 0.5 s -> ~4 samples at 10 Hz
		recorder.record(i * 0.016, Vector3(float(i), 0.0, 0.0), 0.0, 1.0 / 60.0)

		# replay interpolation via GhostCar

		# replay interpolation via GhostCar
	var samples := recorder.finish_lap()
	check.call(samples.size() >= 3, "ghost recorder decimates to ~10 Hz (%d)" % samples.size())
	check.call(recorder.finish_lap().is_empty(), "finish_lap arms the next recording")
	var saved := GhostRecorder.save_best("TEST_TRACK", 61.23, samples)
	check.call(saved, "ghost best lap persists")
	var loaded := GhostRecorder.load_best("TEST_TRACK")
	check.call(loaded.size() == samples.size(), "ghost best lap round-trips")
	check.call(GhostRecorder.load_best("NOPE_TRACK").is_empty(), "missing ghost returns empty")
	# replay interpolation via GhostCar
	var ghost: GhostCar = load("res://scripts/vehicle/ghost_car.gd").new()
	root.add_child(ghost)
	ghost.play_recording(loaded)
	check.call(ghost.visible, "ghost becomes visible with a recording")
	ghost.play_recording([])
	check.call(not ghost.visible, "ghost hides without a recording")
	ghost.queue_free()


# ------------------------------------------------------------ career-lite


static func _test_career_store(check: Callable) -> void:
	CareerStore.record_race("alpha_loop", "race", 1, 8, 61.234, 5)
	CareerStore.record_race("endurance_run", "race", 4, 8, 95.5, 5)
	var stats := CareerStore.stats()
	check.call(int(stats.get("races", 0)) >= 2, "career records races")
	check.call(int(stats.get("wins", 0)) >= 1, "career counts wins")
	check.call(int(stats.get("podiums", 0)) >= 1, "career counts podiums")
	var best: Dictionary = stats.get("best_by_track", {})
	check.call(
		absf(float(best.get("alpha_loop", 0.0)) - 61.234) < 0.01, "career tracks best lap per track"
	)
	# corrupt file falls back to an empty store
	var file := FileAccess.open(CareerStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{corrupt json!!")
	file.close()
	var data := CareerStore.load_data()
	check.call(data.get(CareerStore.KEY_RACES, []).is_empty(), "corrupt career file falls back")
	# cleanup: remove the test store so the dev keeps a clean slate
	DirAccess.remove_absolute(CareerStore.SAVE_PATH)


# ------------------------------------------------------------ hud widgets


static func _test_hud_widgets(check: Callable, root: Node) -> void:
	var track_text := FileAccess.get_file_as_string("res://tracks/alpha_loop.json")
	var track := TrackData.parse(track_text, "res://tracks/alpha_loop.json")
	check.call(track != null, "alpha_loop parses for widget checks")
	if track == null:
		return
		# minimap: build + feed positions (draw itself needs a renderer)

		# nitro fx: layer under the HUD, state updates without a renderer

		# cockpit wheel: builds rim/spokes/leds (all under RimRoot)

		# menu panels compile (constructing them needs autoloads; probe load only)

		# nitro fx: layer under the HUD, state updates without a renderer

		# cockpit wheel: builds rim/spokes/leds (all under RimRoot)

		# menu panels compile (constructing them needs autoloads; probe load only)
	var minimap := MiniMap.new(track.points)
	root.add_child(minimap)
	minimap.update_positions([Vector3(1, 0, 2), Vector3(5, 0, 7)])
	check.call(minimap.custom_minimum_size == Vector2(230, 150), "minimap has a sane default size")
	minimap.queue_free()
	# nitro fx: layer under the HUD, state updates without a renderer
	var fx: NitroFx = load("res://scripts/hud/nitro_fx.gd").new()
	root.add_child(fx)
	fx.set_state(true, 60.0, 0.016)
	fx.set_state(false, 60.0, 0.5)
	check.call(fx.layer == 5, "nitro fx renders under the HUD layers")
	fx.queue_free()
	# cockpit wheel: builds rim/spokes/leds (all under RimRoot)
	var wheel := CockpitWheel.new()
	root.add_child(wheel)
	wheel.update_state(0.5, 0.8)
	var rim_root := wheel.get_child(0)
	check.call(
		rim_root.get_child_count() >= 20,
		"cockpit wheel builds rim/spokes/hub/15 leds (%d)" % rim_root.get_child_count()
	)
	wheel.queue_free()
	# menu panels compile (constructing them needs autoloads; probe load only)
	check.call(load("res://scripts/menu/race_setup.gd") != null, "race_setup.gd compiles")
	check.call(load("res://scripts/menu/career_panel.gd") != null, "career_panel.gd compiles")
	check.call(load("res://scripts/menu/main_menu.gd") != null, "main_menu.gd compiles")


# ------------------------------------------------------------ input feedback


static func _test_input_feedback(check: Callable) -> void:
	var vibration: GDScript = load("res://scripts/ui/vibration.gd")
	check.call(vibration != null, "vibration.gd compiles")
	var constants: Dictionary = vibration.get_script_constant_map()
	var green := 0
	var nitro := 0
	var crash := 0
	for key in constants:  # keys may arrive as StringName — normalize
		var name := String(key)
		if name == "GREEN_FLAG_MS":
			green = int(constants[key])
		elif name == "NITRO_MS":
			nitro = int(constants[key])
		elif name == "CRASH_MS":
			crash = int(constants[key])
	check.call(green > 0 and green < nitro and nitro < crash, "haptic vocabulary is ordered")
