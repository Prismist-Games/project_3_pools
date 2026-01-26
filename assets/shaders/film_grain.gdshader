shader_type canvas_item;
render_mode unshaded;

uniform float grain_speed : hint_range(0.0, 60.0) = 12.0; // 对应原本的 frame_switch_time
uniform float grain_bounce : hint_range(0.0, 1.0) = 0.4;
uniform float grain_scale : hint_range(0.0, 5.0) = 1.0;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05;
uniform sampler2D noise_tex : repeat_enable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

// Vignette params
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.8;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;

varying vec4 vertex_color;

// 伪随机函数
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void vertex() {
	vertex_color = COLOR;
}

void fragment()
{
	vec4 col = texture(SCREEN_TEXTURE, SCREEN_UV);
	
	// 在 Shader 内部计算随机偏移
	// floor(TIME * grain_speed) 会让时间变成阶梯状，实现每秒固定帧数刷新
	float time_step = floor(mod(TIME, 100.0) * grain_speed);
	vec2 random_offset = vec2(
		random(vec2(time_step, 1.234)), 
		random(vec2(time_step, 5.678))
	) * grain_bounce;
	
	// Grain logic
	vec4 noise = texture(noise_tex, mod(SCREEN_UV * grain_scale + random_offset, 1.0));
	
	// Apply grain
	vec3 grain_effect = (noise.rgb - 0.5) * grain_amount;
	vec3 with_grain = col.rgb + grain_effect;
	
	// Vignette logic (Generated)
	float dist = distance(SCREEN_UV, vec2(0.5));
	float v_factor = smoothstep(vignette_radius, vignette_radius - vignette_softness, dist);
	float vignette = mix(1.0, v_factor, vignette_intensity);
	
	COLOR.rgb = with_grain * vignette * vertex_color.rgb;
	COLOR.a = col.a;
}