class_name ChampionshipChecks
extends RefCounted
## Championship checks for 0.8.0: season lifecycle (create / advance / finish),
## points and standings through the league ResultsStore backend, persistence,
## abandon / restart, corrupt-file handling and the menu panel states.
## Call ChampionshipChecks.run(check, root).
##
## NOTE: --script runs do not instantiate autoloads, so autoload identifiers
## (Settings / Sfx) must never appear here. All stores use temp paths under
## user:// and clean up after themselves.

const STATE_PATH := "user://test_champ_state.json"
const RESULTS_PATH := "user://test_champ_results.json"

const CATALOG: Array = [
	{"id": "endurance_run", "name": "ENDURANCE RUN", "path": "res://tracks/endurance_run.json"},
	{"id": "alpha_loop", "name": "ALPHA LOOP", "path": "res://tracks/alpha_loop.json"},
]


static func run(check: Callable, root: Node) -> void:
	print("[championship]")
	_cleanup()
	var store := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	_test_season_lifecycle(check, store)
	_test_points_and_standings(check, store)
	_test_corrupt_and_restart(check)
	_test_panel(check, root)
	_cleanup()


# ------------------------------------------------------------- lifecycle


static func _test_season_lifecycle(check: Callable, store: ChampionshipStore) -> void:
	check.call(not store.is_active(), "no season before creation")
	check.call(store.next_round().is_empty(), "next_round is empty without a season")
	check.call(not store.new_season(4, "legend", 3, []), "new_season fails on an empty catalog")
	check.call(store.new_season(4, "legend", 3, CATALOG), "season created on a 2-track catalog")
	var state := store.state()
	var schedule: Array = state.get("schedule", [])
	check.call(schedule.size() == 4, "schedule holds the requested round count")
	check.call(
		str(schedule[0]) == "endurance_run" and str(schedule[1]) == "alpha_loop",
		"schedule cycles the catalog in order"
	)
	check.call(str(state.get("difficulty", "")) == "legend", "season difficulty stored")
	check.call(int(state.get("laps", 0)) == 3, "season lap count stored")
	var names: Array = state.get("names", [])
	check.call(names.size() == 8, "grid roster has 8 fictional names")
	check.call(str(names[0]) == ChampionshipStore.PLAYER_NAME, "roster slot 0 is the player")
	check.call(str(names[1]) == "K. VOSS", "roster holds the first fictional AI name")
	# Replacing with a 2-round season (invalid difficulty -> pro fallback).
	check.call(store.new_season(2, "banana", 3, CATALOG), "season replaced with a new one")
	check.call(
		str(store.state().get("difficulty", "")) == "pro", "invalid difficulty falls back to pro"
	)
	check.call(store.state().get("schedule", []).size() == 2, "replacement schedule applied")
	var round_info := store.next_round()
	check.call(
		(
			not round_info.is_empty()
			and int(round_info.get("index", -1)) == 0
			and str(round_info.get("track_id", "")) == "endurance_run"
			and int(round_info.get("laps", 0)) == 3
			and str(round_info.get("difficulty", "")) == "pro"
		),
		"next_round describes round 1 with laps and difficulty"
	)
	check.call(store.is_active(), "is_active once the season runs")
	check.call(store.record_result([]).is_empty(), "record_result rejects an empty classification")
	var first := store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7]))
	check.call(not first.is_empty(), "record_result accepts the race classification")
	check.call(int(first.get("round_index", -1)) == 0, "result recorded for round 1")
	check.call(not bool(first.get("season_done", true)), "season continues after round 1")
	var history: Array = store.player_results()
	check.call(
		history.size() == 1 and int(history[0].get("points", -1)) == 25,
		"player points for the round recorded (P1 -> 25)"
	)
	var second := store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7]))
	check.call(int(second.get("round_index", -1)) == 1, "second round recorded as round 2")
	check.call(bool(second.get("season_done", false)), "season completes after the last round")
	check.call(store.next_round().is_empty(), "next_round is empty on a finished season")
	check.call(not store.is_active(), "finished season is not active")
	check.call(
		store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7])).is_empty(),
		"record_result is rejected on a finished season"
	)


# ------------------------------------------------- points and standings


static func _test_points_and_standings(check: Callable, store: ChampionshipStore) -> void:
	var table := store.standings()
	check.call(table.size() == 8, "standings cover the whole grid")
	var top: Dictionary = table[0]
	check.call(
		(
			str(top.get("name", "")) == ChampionshipStore.PLAYER_NAME
			and int(top.get("points", 0)) == 50
		),
		"player leads with 50 pts after two wins"
	)
	check.call(int(top.get("wins", 0)) == 2, "two wins credited to the champion")
	var second_row: Dictionary = table[1]
	check.call(
		str(second_row.get("name", "")) == "K. VOSS" and int(second_row.get("points", 0)) == 36,
		"AI points aggregate across rounds (K. VOSS 18+18)"
	)
	var total := 0
	for entry: Dictionary in table:
		total += int(entry.get("points", 0))
	check.call(total == 196, "standings points total matches two full point payouts")


## 8-car classification from a grid order: order[0] wins, order[i] is P(i+1).
## Car 0 is the player; its slot inside the order decides the player result.
static func _classification(grid_order: Array) -> Array:
	var out: Array = []
	for position in range(grid_order.size()):
		var lap := 90.0 + float(position) * 0.5
		(
			out
			. append(
				{
					"position": position + 1,
					"car_index": int(grid_order[position]),
					"laps": 3,
					"best_lap": lap,
					"finish_time": 270.0 + float(position) * 2.0,
				}
			)
		)
	return out


# --------------------------------------------- persistence and restart


static func _test_corrupt_and_restart(check: Callable) -> void:
	var fresh := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	var state := fresh.state()
	check.call(bool(state.get("done", false)), "finished season persists across instances")
	check.call(str(state.get("season_key", "")) == "champ-1", "season key stored in the state")
	fresh.abandon()
	check.call(fresh.state().is_empty(), "abandon clears the season")
	check.call(
		ChampionshipStore.new(STATE_PATH, RESULTS_PATH).state().is_empty(),
		"abandon persists across instances"
	)
	var restart := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	restart.new_season(6, "rookie", 5, CATALOG)
	check.call(
		str(restart.state().get("season_key", "")) == "champ-2",
		"new season after abandon gets a fresh key"
	)
	check.call(restart.state().get("schedule", []).size() == 6, "six-round calendar supported")
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	file.store_string("{{{not json")
	file.flush()
	file.close()
	var broken := ChampionshipStore.new(STATE_PATH, RESULTS_PATH)
	check.call(broken.state().is_empty(), "corrupt state file degrades to no season")
	check.call(broken.next_round().is_empty(), "corrupt state yields no round")
	check.call(broken.standings().is_empty(), "corrupt state yields no standings")


# --------------------------------------------------------------- panel


static func _test_panel(check: Callable, root: Node) -> void:
	# Runtime load (never a static class reference): the panel touches
	# autoload identifiers, so --script startup must not compile it early.
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
	check.call(_has_label(panel, "NEW SEASON"), "panel shows season setup without a season")
	store.new_season(4, "pro", 5, CATALOG)
	store.record_result(_classification([0, 1, 2, 3, 4, 5, 6, 7]))
	panel.rebuild()
	check.call(_has_label(panel, "CALENDAR"), "panel shows the calendar of an active season")
	check.call(_has_label(panel, "STANDINGS"), "panel shows standings of an active season")
	check.call(_has_label(panel, "NEXT"), "panel marks the upcoming round")
	check.call(_has_label_prefix(panel, "START ROUND 2"), "panel offers the next round button")
	panel.rebuild()
	check.call(store.next_round().get("index", -1) == 1, "panel rebuild keeps the store intact")
	store.record_result(_classification([1, 0, 2, 3, 4, 5, 6, 7]))
	store.record_result(_classification([1, 0, 2, 3, 4, 5, 6, 7]))
	store.record_result(_classification([1, 0, 2, 3, 4, 5, 6, 7]))
	panel.rebuild()
	check.call(_has_label(panel, "SEASON COMPLETE"), "panel shows the completed season")
	check.call(bool(store.state().get("done", false)), "all four rounds recorded")
	panel.queue_free()


## Depth-first search for a Label with the exact text.
static func _has_label(node: Node, text: String) -> bool:
	if node is Label and str((node as Label).text) == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


## Depth-first search for any Label or Button text starting with the prefix.
static func _has_label_prefix(node: Node, prefix: String) -> bool:
	if (node is Label or node is Button) and str(node.get("text")).begins_with(prefix):
		return true
	for child in node.get_children():
		if _has_label_prefix(child, prefix):
			return true
	return false


static func _cleanup() -> void:
	for path in [STATE_PATH, RESULTS_PATH, STATE_PATH + ".tmp", RESULTS_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
