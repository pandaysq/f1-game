class_name MiniMap
extends PanelContainer
## Track map widget (0.6.0): F1-broadcast style — white centerline polyline
## on a dark skewed panel, red dot for the player car, dim dots for the rest.
## Top-down (north-up) fit of the track bounding box, rebuilt per track.
## update_positions() is called from the HUD every rendered frame.

const PLAYER_COLOR := F1Theme.RED
const AI_COLOR := Color(1, 1, 1, 0.55)
const TRACK_COLOR := Color(1, 1, 1, 0.65)
const START_COLOR := F1Theme.GREEN

var _view: TrackView
var _player_index := 0


func _init(track_points: Array[Vector3], map_size: Vector2 = Vector2(230, 150)) -> void:
	add_theme_stylebox_override("panel", F1Theme.panel_style())
	custom_minimum_size = map_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = TrackView.new()
	var flat := PackedVector2Array()
	for p in track_points:
		flat.append(Vector2(p.x, p.z))
	_view.map_points = flat
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


## Which entry of update_positions() is the player (default 0 = player car).
func set_player_index(index: int) -> void:
	_player_index = index


## World-space positions of all cars, mapped through the same track fit.
func update_positions(world_positions: Array[Vector3]) -> void:
	_view.car_points.clear()
	for pos in world_positions:
		_view.car_points.append(Vector2(pos.x, pos.z))
	_view.player_index = _player_index
	_view.queue_redraw()


class TrackView:
	extends Control
	## Draws the projected track polyline + live car dots. The fit transform
	## (scale + centering) is recomputed on resize only, not per frame.

	var map_points: PackedVector2Array = PackedVector2Array()
	var car_points: Array[Vector2] = []
	var player_index := 0

	var _scale := 1.0
	var _offset := Vector2.ZERO
	var _dirty_fit := true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_dirty_fit = true
			queue_redraw()

	func _recompute_fit() -> void:
		if map_points.size() < 2 or size.x <= 0.0:
			return
		var min_v := Vector2(INF, INF)
		var max_v := Vector2(-INF, -INF)
		for p in map_points:
			min_v = min_v.min(p)
			max_v = max_v.max(p)
		var span := (max_v - min_v).max(Vector2.ONE)
		var pad := 14.0
		var avail := (size - Vector2(pad * 2.0, pad * 2.0)).max(Vector2.ONE)
		_scale = minf(avail.x / span.x, avail.y / span.y)
		var fitted := span * _scale
		_offset = (size - fitted) * 0.5 - min_v * _scale
		_dirty_fit = false

	func _to_local(point: Vector2) -> Vector2:
		return point * _scale + _offset

	func _draw() -> void:
		if map_points.size() < 2 or size.x <= 0.0:
			return
		if _dirty_fit:
			_recompute_fit()
		var pts := PackedVector2Array()
		pts.resize(map_points.size())
		for i in range(map_points.size()):
			pts[i] = _to_local(map_points[i])
		draw_polyline(pts, TRACK_COLOR, 2.5, true)
		# start/finish marker on the first centerline point
		draw_circle(pts[0], 3.0, START_COLOR)
		for i in range(car_points.size()):
			var is_player := i == player_index
			var color := PLAYER_COLOR if is_player else AI_COLOR
			draw_circle(_to_local(car_points[i]), 5.0 if is_player else 3.5, color)
