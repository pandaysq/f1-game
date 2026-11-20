extends SceneTree
## Track validator (headless). Run:
##   godot --headless --path . --script res://tracks/validate_tracks.gd
##
## Thin wrapper: scans tracks/*.json and runs TrackValidator on each.

const TRACKS_DIR := "res://tracks"


func _initialize() -> void:
	print("== Apex GP: track validator ==")
	var files := _list_track_files()
	if files.is_empty():
		print("No track files found yet.")
		quit(0)
		return

	var total_failures := 0
	for path in files:
		var track := TrackData.load_from(path)
		if track == null:
			printerr("%s: cannot parse" % path)
			total_failures += 1
			continue
		var problems := TrackValidator.validate(track)
		if problems.is_empty():
			print(
				(
					"  OK   %s (%d points, lap ~%.0f m)"
					% [path, track.point_count(), track.lap_length()]
				)
			)
		else:
			total_failures += problems.size()
			for problem in problems:
				printerr("  FAIL %s: %s" % [path, problem])

	if total_failures == 0:
		print("VALIDATION PASSED (%d track file(s))" % files.size())
		quit(0)
	else:
		printerr("VALIDATION FAILED (%d problem(s))" % total_failures)
		quit(1)


func _list_track_files() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(TRACKS_DIR)
	if dir == null:
		printerr("Cannot open directory: %s" % TRACKS_DIR)
		return files
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			files.append("%s/%s" % [TRACKS_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files
