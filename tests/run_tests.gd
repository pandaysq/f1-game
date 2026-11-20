extends SceneTree
## Phase 0 smoke tests (headless). Run:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Verifies the project skeleton is consistent: physics tick rate, main scene,
## input actions, autoload. Physics behavior tests arrive in Phase 1.

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
        print("== Apex GP: Phase 0 smoke tests ==")
        _test_physics_config()
        _test_application_config()
        _test_input_actions()
        _test_autoload()
        _print_summary()
        quit(1 if not _failures.is_empty() else 0)


func _check(condition: bool, test_name: String) -> void:
        _checks += 1
        if condition:
                print("  OK   %s" % test_name)
        else:
                _failures.append(test_name)
                print("  FAIL %s" % test_name)


func _test_physics_config() -> void:
        print("[physics]")
        var ticks: Variant = ProjectSettings.get_setting(
                "physics/common/physics_ticks_per_second", 0
        )
        _check(ticks == 120, "physics tick rate is 120 Hz")


func _test_application_config() -> void:
        print("[application]")
        var main_scene: Variant = ProjectSettings.get_setting(
                "application/run/main_scene", ""
        )
        _check(main_scene == "res://scenes/main.tscn", "main scene is configured")


func _test_input_actions() -> void:
        print("[input]")
        var required := [
                "throttle", "brake", "steer_left", "steer_right", "nitro",
                "shift_up", "shift_down", "reset_car", "toggle_camera", "toggle_debug",
        ]
        for action in required:
                var defined: bool = InputMap.has_action(action)
                _check(defined, "action '%s' is defined" % action)
                if defined:
                        var events: Array = InputMap.action_get_events(action)
                        _check(not events.is_empty(), "action '%s' has events" % action)


func _test_autoload() -> void:
        print("[autoload]")
        var settings_path: Variant = ProjectSettings.get_setting("autoload/Settings", "")
        _check(
                settings_path == "*res://scripts/settings.gd",
                "Settings autoload is registered"
        )


func _print_summary() -> void:
        if _failures.is_empty():
                print("ALL TESTS PASSED (%d checks)" % _checks)
        else:
                printerr("%d of %d checks failed:" % [_failures.size(), _checks])
                for failure in _failures:
                        printerr("  - %s" % failure)
