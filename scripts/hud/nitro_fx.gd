class_name NitroFx
extends CanvasLayer
## Boost overlay (0.6.0): radial speed lines + dark vignette that breathe in
## while nitro thrusts and bleed out when it ends. Pure canvas shader, one
## full-rect rect — cheap enough for phones. Sits under the HUD layers.

const SHADER_CODE := """
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
        vec2 uv = UV;
        vec2 center = vec2(0.5, 0.46);
        vec2 dir = uv - center;
        dir.y *= 1.35;  // widescreen compensation
        float r = length(dir);
        float ang = atan(dir.y, dir.x);

        // radiating speed lines: 9 lanes per turn, scrolling outwards
        float lines = 0.0;
        for (int i = 0; i < 6; i++) {
                float fi = float(i);
                float lane = fract(ang / 6.2831853 * 9.0 + fi * 0.31 + TIME * (1.6 + fi * 0.23));
                float line = smoothstep(0.5, 0.0, abs(lane - 0.5)) * smoothstep(0.22, 0.9, r);
                lines += line;
        }
        lines *= 0.30;

        // dark vignette hugging the edges
        float vig = smoothstep(0.42, 1.02, r);
        float edge = clamp(vig * 0.62 + lines, 0.0, 1.0) * strength;
        COLOR = vec4(0.0, 0.0, 0.0, edge);
}
"""

const LAYER_INDEX := 5

var _rect: ColorRect
var _material: ShaderMaterial
var _strength := 0.0
var _target := 0.0


func _init() -> void:
	layer = LAYER_INDEX
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = sh
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Called every physics tick: active = nitro thrusting now.
func set_state(active: bool, speed: float, delta: float) -> void:
	if _material == null:
		return
	_target = 1.0 if (active and speed > 20.0) else 0.0
	var rate := 9.0 if _target > _strength else 3.5
	_strength = lerpf(_strength, _target, minf(rate * delta, 1.0))
	_material.set_shader_parameter("strength", _strength)
