class_name Vibration
extends RefCounted
## Haptic feedback helper (0.6.0). No-ops on non-touch devices (desktop QA,
## headless CI) and when the user disabled haptics in settings. Intensity
## vocabulary: green flag < nitro pulse < crash.

const GREEN_FLAG_MS := 40
const NITRO_MS := 60
const CRASH_MS := 180


static func _allowed() -> bool:
	return Settings.vibration and DisplayServer.is_touchscreen_available()


static func green_flag() -> void:
	if _allowed():
		Input.vibrate_handheld(GREEN_FLAG_MS)


static func nitro_pulse() -> void:
	if _allowed():
		Input.vibrate_handheld(NITRO_MS, 0.4)


## strength 0..1 scales the amplitude of the crash buzz.
static func crash(strength: float = 1.0) -> void:
	if _allowed():
		Input.vibrate_handheld(CRASH_MS, clampf(strength, 0.2, 1.0))
