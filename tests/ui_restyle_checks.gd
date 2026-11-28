class_name UiRestyleChecks
extends RefCounted
## UI restyle 0.9.0 checks: DriverRoster identity mapping, UiIcons loading,
## F1Theme helper widgets (sep / chip / back_row / stub_button / fit_width),
## the championship panel in all three states without string separators, and
## a source sweep that keeps "///" separators out of the codebase for good.
## Call UiRestyleChecks.run(check, root).
##
## NOTE: --script runs do not instantiate autoloads, so autoload identifiers
## (Settings / Sfx) must never be CALLED here; lambdas inside theme factories
## only fire on real presses, which the checks never do.

const STATE_PATH := "user://test_restyle_state.json"
const RESULTS_PATH := "user://test_restyle_results.json"

const CATALOG: Array = [
	{"id": "endurance_run", "name": "ENDURANCE RUN", "path": "res://tracks/endurance_run.json"},
	{"id": "alpha_loop", "name": "ALPHA LOOP", "path": "res://tracks/alpha_loop.json"},
]


static func run(check: Callable, root: Node) -> void:
	print("[ui_restyle]")
	_test_roster(check)
	_test_icons(check)
	_test_theme_helpers(check)
	_test_no_slash_sources(check)
	_test_championship_panel_texts(check, root)
	_cleanup()


# ------------------------------------------------------------------ roster


static func _test_roster(check: Callable) -> void:
	check.call(DriverRoster.display_name(0) == "YOU", "roster slot 0 is the player")
	check.call(DriverRoster.display_name(1) == "K. VOSS", "first AI slot is K. VOSS")
	check.call(DriverRoster.display_name(7) == "P. DUBOIS", "last AI slot is P. DUBOIS")
	check.call(DriverRoster.display_name(9) == "AI9", "out-of-grid slots fall back to AI<i>")
	check.call(
		DriverRoster.display_name(2, ["YOU", "A B", "X Y"]) == "X Y",
		"season roster overrides the base names"
	)
	check.call(DriverRoster.tag(0) == "YOU", "player tag is YOU")
	check.call(DriverRoster.tag(1) == "VOS", "broadcast tags map by slot (VOS)")
	check.call(DriverRoster.tag(7) == "DUB", "broadcast tags map by slot (DUB)")
	check.call(DriverRoster.tag(9) == "AI9", "tag fallback trims the fallback name")
	check.call(DriverRoster.tower_color(0) == F1Theme.RED, "player tower bar is F1 red")
	check.call(
		DriverRoster.tower_color(1) != DriverRoster.tower_color(2),
		"AI tower bars are distinct per driver"
	)
	var dim := DriverRoster.tower_color(9)
	check.call(dim.a < 1.0, "unknown slots get a dim bar")


# ------------------------------------------------------------------- icons


static func _test_icons(check: Callable) -> void:
	for name in UiIcons.NAMES:
		check.call(UiIcons.texture(name) != null, "icon loads: %s" % name)
	var rect := UiIcons.icon("stopwatch", 16, F1Theme.YELLOW)
	check.call(rect.texture != null, "icon factory returns a textured rect")
	check.call(rect.modulate == F1Theme.YELLOW, "icon factory tints through modulate")
	var cached := UiIcons.texture("stopwatch")
	check.call(UiIcons.texture("stopwatch") == cached, "icon textures are cached")


# ------------------------------------------------------------ theme helpers


static func _test_theme_helpers(check: Callable) -> void:
	var sep := F1Theme.sep()
	var sb: StyleBoxFlat = sep.get_theme_stylebox("panel")
	check.call(sb != null and sb.skew != Vector2.ZERO, "sep is a skewed divider slab")
	check.call(sb.bg_color == F1Theme.RED, "sep defaults to F1 red")
	check.call(
		F1Theme.fit_width(["ROOKIE"], 20, 86.0) > 86.0,
		"fit_width grows past the minimum for wide labels"
	)
	check.call(
		F1Theme.fit_width(["8"], 20, 86.0) == 86.0, "fit_width keeps the minimum for narrow labels"
	)
	var row := F1Theme.back_row(func() -> void: pass)
	var has_back := false
	for child in row.get_children():
		if child is Button and (child as Button).text == "BACK":
			has_back = true
	check.call(has_back, "back_row carries a BACK button")
	var stub := F1Theme.stub_button("MULTIPLAYER", "world")
	check.call(stub.disabled, "stub buttons are disabled")
	check.call(stub.icon != null, "stub buttons carry an icon")
	var chip := F1Theme.chip("PRO AI")
	var chip_label: Variant = chip.get_child(0)
	check.call(
		chip is PanelContainer and chip_label is Label and (chip_label as Label).text == "PRO AI",
		"chip is a panel with the given label"
	)
	var heading := F1Theme.heading("RACE RESULT", 32, F1Theme.RED, "checkered-flag")
	check.call(heading.get_child(0) is TextureRect, "heading prepends the requested icon")


# ------------------------------------------------- no string separators, ever


## The double-space-padded "///" signature is banned across scripts and
## tests: UI rows compose from F1Theme.sep + icons instead.
static func _test_no_slash_sources(check: Callable) -> void:
	var bad: PackedStringArray = []
	_scan_dir("res://scripts", bad)
	_scan_dir("res://tests", bad)
	check.call(bad.is_empty(), "no /// separators in sources (%s)" % " ".join(bad))


static func _scan_dir(path: String, bad: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

		# the needle is assembled so this file never carries it literally
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, bad)

				# the needle is assembled so this file never carries it literally
		elif entry.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(full)
			# the needle is assembled so this file never carries it literally
			if text.contains("  " + "///" + "  "):
				bad.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


# --------------------------------------------------- championship panel texts


static func _test_championship_panel_texts(check: Callable, root: Node) -> void:
	var panel_script: GDScript = load("res://scripts/menu/championship_panel.gd")
	check.call(panel_script != null, "championship_panel.gd compiles")
	if panel_script == null:
		return
	var store := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	var panel: Control = panel_script.new()
	panel.setup_catalog(CATALOG, [3, 5, 8], ["rookie", "pro", "legend"])
	panel.setup_store(store)
	root.add_child(panel)

	panel.rebuild()
	var texts := PackedStringArray()
	_collect_texts(panel, texts)
	check.call(_none_contains(texts, "///"), "setup state has no /// separators")
	check.call(_has_text(texts, "ROOKIE"), "difficulty chips render uppercase labels")

	store.new_season(4, "pro", 5, CATALOG)
	panel.rebuild()
	texts = PackedStringArray()
	_collect_texts(panel, texts)
	check.call(_none_contains(texts, "///"), "active season has no /// separators")
	check.call(_has_text(texts, "ROUND 1 OF 4"), "round header names the round")
	check.call(_has_text(texts, "NO POINTS YET"), "empty standings show a short hint")

	store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7]))
	panel.rebuild()
	texts = PackedStringArray()
	_collect_texts(panel, texts)
	check.call(_has_text(texts, "ROUND 2 OF 4"), "round header advances after a win")
	check.call(_has_text(texts, "START ROUND 2"), "start button names the round only")

	for i in range(3):
		store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7]))
	panel.rebuild()
	texts = PackedStringArray()
	_collect_texts(panel, texts)
	check.call(_none_contains(texts, "///"), "finished season has no /// separators")
	check.call(_has_text(texts, "SEASON COMPLETE"), "finished season keeps its title")
	check.call(_has_text(texts, "CHAMPION"), "champion row keeps the caption")
	check.call(_has_text(texts, "4 ROUNDS"), "season facts render as chips")

	panel.queue_free()


## Depth-first collection of every Label/Button text.
static func _collect_texts(node: Node, out: PackedStringArray) -> void:
	if node is Label or node is Button:
		out.append(str(node.get("text")))
	for child in node.get_children():
		_collect_texts(child, out)


static func _none_contains(texts: PackedStringArray, needle: String) -> bool:
	for t in texts:
		if t.contains(needle):
			return false
	return true


static func _has_text(texts: PackedStringArray, needle: String) -> bool:
	return texts.has(needle)


## 8-car classification with the player slot given first (P1).
static func _classification(player_first_order: Array) -> Array:
	var out: Array = []
	for position in range(player_first_order.size()):
		(
			out
			. append(
				{
					"position": position + 1,
					"car_index": int(player_first_order[position]),
					"laps": 3,
					"best_lap": 90.0 + float(position) * 0.5,
					"finish_time": 270.0 + float(position) * 2.0,
				}
			)
		)
	return out


static func _cleanup() -> void:
	for path in [STATE_PATH, RESULTS_PATH, STATE_PATH + ".tmp", RESULTS_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
