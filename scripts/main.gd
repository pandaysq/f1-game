extends Node3D
## Phase 0 main scene: empty world, sun, ground plane and debug overlay.
##
## Gameplay (car, track, timing) arrives in Phase 1; this scene exists so the
## project boots end-to-end and CI has something real to run.

@onready var debug_overlay: CanvasLayer = $DebugOverlay


func _ready() -> void:
	debug_overlay.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
