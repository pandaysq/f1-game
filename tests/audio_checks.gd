class_name AudioChecks
extends RefCounted
## Audio pack checks (0.5.0), extracted from run_tests.gd to keep the test
## suite under the gdlint file-size limit. Call AudioChecks.run(_check, root).


static func run(check: Callable, root: Node) -> void:
	print("[audio]")
	# engine loops: six forward-looped WAVs (rpm bands)
	for i in range(6):
		var stream := load("res://assets/audio/engine/engine_%d.wav" % i) as AudioStreamWAV
		check.call(stream != null, "engine_%d.wav loads" % i)
		if stream != null:
			(
				check
				. call(
					stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
					"engine_%d.wav is forward-looped" % i,
				)
			)

		# sfx.gd compiles + sound table fully loadable

		# race audio: band weight math (statics, no audio device needed)

		# nitro tank math (static, config-driven)

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	var skid := load("res://assets/audio/tires/skid_loop.wav") as AudioStreamWAV
	(
		check
		. call(
			skid != null and skid.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"skid loop is forward-looped",
		)
	)
	var nitro := load("res://assets/audio/nitro/nitro_loop.wav") as AudioStreamWAV
	(
		check
		. call(
			nitro != null and nitro.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"nitro loop is forward-looped",
		)
	)
	# sfx.gd compiles + sound table fully loadable
	var sfx_script: GDScript = load("res://scripts/audio/sfx.gd")
	check.call(sfx_script != null, "sfx.gd compiles")
	if sfx_script == null:
		return

		# race audio: band weight math (statics, no audio device needed)

		# nitro tank math (static, config-driven)

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	var sounds: Dictionary = sfx_script.get_script_constant_map().get("SOUNDS", {})
	check.call(sounds.size() >= 11, "Sfx sound table is populated (%d entries)" % sounds.size())
	var missing := 0
	for key in sounds:
		if load(sounds[key]) == null:
			missing += 1

		# race audio: band weight math (statics, no audio device needed)

		# nitro tank math (static, config-driven)

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	check.call(missing == 0, "all Sfx streams load (missing %d)" % missing)
	var registered: Variant = ProjectSettings.get_setting("autoload/Sfx", "")
	check.call(registered == "*res://scripts/audio/sfx.gd", "Sfx autoload is registered")
	var sfx_node: Node = root.get_node_or_null("Sfx")
	check.call(sfx_node != null and sfx_node.has_method("play"), "Sfx runtime node is alive")
	if sfx_node != null:
		sfx_node.call("play", "beep", -6.0)
		# race audio: band weight math (statics, no audio device needed)

		# nitro tank math (static, config-driven)

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	var ra_script: GDScript = load("res://scripts/audio/race_audio.gd")
	check.call(ra_script != null, "race_audio.gd compiles")
	if ra_script != null:
		var ra: Node = ra_script.new(null)
		var idle_w: Array = ra.call("band_weights", 0.0)
		check.call(idle_w.size() == 6 and absf(idle_w[0] - 1.0) < 0.001, "engine band 0 owns idle")
		var red_w: Array = ra.call("band_weights", 1.0)
		check.call(red_w.size() == 6 and absf(red_w[5] - 1.0) < 0.001, "engine band 5 owns redline")
		var mid_w: Array = ra.call("band_weights", 0.5)
		var mid_ok: bool = absf(mid_w[2] - mid_w[3]) < 0.01 and mid_w[2] > 0.5 and mid_w[0] < 0.001
		check.call(mid_ok, "mid-rpm splits between adjacent bands")
		var norm: float = ra.call("engine_norm_rpm", 3000.0, 3000.0, 13000.0)
		check.call(absf(norm) < 0.001, "engine_norm_rpm idles at 0")
		ra.free()
		# nitro tank math (static, config-driven)

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	var car_script: GDScript = load("res://scripts/vehicle/car.gd")
	check.call(car_script != null, "car.gd compiles")
	if car_script != null:
		var cfg := {"capacity_s": 3.0, "regen_per_s": 0.5}
		var drained: float = car_script.call("nitro_tank_step", 3.0, true, 1.0, cfg)
		check.call(absf(drained - 2.0) < 0.001, "nitro tank drains while boosting")
		var refilled: float = car_script.call("nitro_tank_step", 0.0, false, 2.0, cfg)
		check.call(absf(refilled - 1.0) < 0.001, "nitro tank refills while idle")

		# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	var vdata: Dictionary = (
		JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/vehicle.json"))
		as Dictionary
	)
	check.call(vdata.get("nitro", {}).has("thrust_n"), "vehicle.json defines the nitro block")
	# compile probe: main.gd pulls the RaceAudio/RaceHud/F1Theme/Sfx chain
	check.call(load("res://scripts/main.gd") != null, "main.gd compiles (audio hooks)")
