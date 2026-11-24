extends SceneTree
## API probe: verify Godot 4.5.1 APIs used by the new UI code.


func _initialize() -> void:
	var lines: Array[String] = []

	var sb := StyleBoxFlat.new()
	lines.append(
		"StyleBoxFlat has skew: %s" % ["skew" in sb.get_property_list().map(func(p): return p.name)]
	)

	lines.append("Viewport.MSAA_4X: %s" % str(Viewport.MSAA_4X))
	lines.append("Viewport.MSAA_2X: %s" % str(Viewport.MSAA_2X))
	lines.append("Viewport.MSAA_DISABLED: %s" % str(Viewport.MSAA_DISABLED))

	var tsb := TouchScreenButton.new()
	tsb.texture_pressed = null  # property exists?
	lines.append("TouchScreenButton.texture_pressed: %s" % str(tsb.get("texture_pressed")))

	var f: Font = load("res://assets/ui/fonts/TitilliumWeb-Black.ttf")
	lines.append("Font loaded: %s (%s)" % [str(f != null), str(f.get_class()) if f else "-"])

	var b := Button.new()
	b.add_theme_font_override("font", f)
	lines.append("Button font override ok: %s" % str(b.get_theme_font("font") == f))

	lines.append("ConfigFile.save exists: %s" % str(ConfigFile.new().has_method("save")))
	lines.append("error_string exists: %s" % str(error_string(OK) == "OK"))
	lines.append(
		(
			"SceneTree paused prop: %s"
			% str("paused" in get_property_list().map(func(p): return p.name))
		)
	)

	for l in lines:
		print("PROBE | ", l)
	quit(0)
