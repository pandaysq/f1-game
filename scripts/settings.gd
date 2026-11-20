extends Node
## Global settings autoload (Phase 0).
##
## Stores assist toggles and quality preset stub. Gameplay code must read
## assists from here, never from hardcoded values, so league rules (Phase 7)
## and the setup screen (Phase 8) can override them per session.

## Assist flags. All individual toggles per master prompt section 4.
## Defaults chosen for a new player: forgiving but honest physics.
var assists: Dictionary = {
	"auto_gearbox": true,
	"steering_assist": true,
	"stability_control": true,
	"abs": true,
	"traction_control": true,
	"racing_line": false,
}

## Quality preset stub ("low" / "medium" / "high"), used in Phase 9.
var quality: String = "high"


func _ready() -> void:
	print("[Settings] ready, assists=%s quality=%s" % [str(assists.keys()), quality])
