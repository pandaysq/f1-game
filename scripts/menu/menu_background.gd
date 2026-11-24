class_name MenuBackground
extends ColorRect
## Animated F1-broadcast backdrop: dark gradient with slow diagonal light
## streaks (the flowing intro/transition look) plus a soft red floor glow.
## Pure canvas shader, no textures, cheap enough for phones.

const SHADER_CODE := """
shader_type canvas_item;

float streak(float pos, float width) {
        return smoothstep(width, 0.0, abs(pos - 0.5));
}

void fragment() {
        vec2 uv = UV;
        float x = uv.x + uv.y * 0.55;
        vec3 col = mix(vec3(0.050, 0.055, 0.085), vec3(0.085, 0.095, 0.135), uv.y);

        // three flowing diagonal streaks: two red, one cool white
        for (int i = 0; i < 3; i++) {
                float fi = float(i);
                float sp = 0.045 + fi * 0.030;
                float pos = fract(x * 0.55 + fi * 0.37 + TIME * sp);
                float w = 0.05 + fi * 0.018;
                vec3 tint = mix(vec3(0.92, 0.10, 0.05), vec3(0.72, 0.74, 0.80), fi * 0.5);
                col = mix(col, tint, streak(pos, w) * (0.12 - fi * 0.02));
        }

        // fast thin speed lines
        for (int j = 0; j < 4; j++) {
                float fj = float(j);
                float pos2 = fract(x * 1.4 + fj * 0.61 + TIME * (0.12 + fj * 0.03));
                col += vec3(1.0) * smoothstep(0.012, 0.0, abs(pos2 - 0.5)) * 0.05;
        }

        // red glow hugging the bottom-left, vignette elsewhere
        float glow = smoothstep(1.15, 0.3, distance(uv, vec2(0.12, 1.08)));
        col = mix(col, vec3(0.55, 0.035, 0.02), glow * 0.4);
        float vig = smoothstep(1.3, 0.4, distance(uv, vec2(0.5, 0.5)));
        col *= mix(0.5, 1.0, vig);

        COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	material = mat
