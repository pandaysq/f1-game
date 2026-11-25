class_name TrackLimits
extends RefCounted
## Track-limits rules (0.6.0): an excursion counts as a cut when the car is
## beyond the road+kerb edge with real pace for a sustained moment. The
## third cut in a lap invalidates the lap (Time Trial deletes the lap time;
## the race HUD warns). The counter resets on every lap crossing.
##
## Pure logic — fed off-track flags each physics tick, unit-testable.

signal cut_committed(count: int)
signal lap_invalidated(count: int)

const LIMITS_PER_LAP := 3
const SUSTAIN_S := 1.0
const MIN_SPEED_MPS := 8.0

var cuts_this_lap: int = 0

var _off_time := 0.0
var _in_cut := false


## Call every physics tick. off_track = car beyond road + margin edge.
func update(off_track: bool, speed: float, delta: float) -> void:
	if off_track and speed > MIN_SPEED_MPS:
		_off_time += delta
		if _off_time >= SUSTAIN_S and not _in_cut:
			_in_cut = true
			cuts_this_lap += 1
			if cuts_this_lap >= LIMITS_PER_LAP:
				lap_invalidated.emit(cuts_this_lap)
			else:
				cut_committed.emit(cuts_this_lap)
	else:
		# brief kerb hops reset the accumulation; a committed cut needs the
		# car to come back onto the road before the next one can count
		_off_time = 0.0
		_in_cut = false


## Called on every lap crossing (start/finish).
func reset_lap() -> void:
	cuts_this_lap = 0
	_off_time = 0.0
	_in_cut = false


func lap_valid() -> bool:
	return cuts_this_lap < LIMITS_PER_LAP
