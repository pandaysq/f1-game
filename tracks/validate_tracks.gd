extends SceneTree
## Track validator (headless). Run:
##   godot --headless --path . --script res://tracks/validate_tracks.gd
##
## Phase 0: scans tracks/*.json, checks JSON integrity and required fields.
## Phase 1 adds full geometric checks (closed loop, self-intersections,
## width, timing lines, NaN) per tracks/README.md.

const TRACKS_DIR := "res://tracks"
const REQUIRED_FIELDS := ["name", "closed", "centerline"]


func _initialize() -> void:
	print("== Apex GP: track validator ==")
	var files := _list_track_files()
	if files.is_empty():
		print("No track files found yet (alpha_loop.json arrives in Phase 1).")
		quit(0)
		return

	var total_failures := 0
	for path in files:
		total_failures += _validate_track(path)

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


func _validate_track(path: String) -> int:
	var failures := 0
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		printerr("%s: file is empty" % path)
		return 1

	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		printerr("%s: invalid JSON" % path)
		return 1

	for field in REQUIRED_FIELDS:
		if not (data as Dictionary).has(field):
			printerr("%s: missing required field '%s'" % [path, field])
			failures += 1

	var centerline: Variant = (data as Dictionary).get("centerline", [])
	if not (centerline is Array) or (centerline as Array).is_empty():
		printerr("%s: centerline must be a non-empty array" % path)
		failures += 1
	else:
		for i in range((centerline as Array).size()):
			var point: Variant = (centerline as Array)[i]
			if not (point is Dictionary):
				printerr("%s: centerline[%d] is not an object" % [path, i])
				failures += 1
	return failures
