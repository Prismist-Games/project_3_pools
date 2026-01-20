shader_type canvas_item;

uniform float circle_size : hint_range(0.0, 1.0) = 0.4;
uniform float outline_width : hint_range(0.0, 0.1) = 0.01;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ratio_width = 1.0;
uniform float ratio_height = 1.0;
varying vec4 vertex_color; 

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	float ratio = ratio_width / ratio_height;
	float dist = distance(vec2(0.5, 0.5), vec2(mix(0.5, UV.x, ratio), UV.y));
	
	// 圆形主体掩码 (dist < circle_size 为1)
	float circle_mask = 1.0 - step(circle_size, dist);
	
	// 描边掩码 (circle_size < dist < circle_size + outline_width 为1)
	float outline_mask = (1.0 - step(circle_size + outline_width, dist)) * step(circle_size, dist);
	
	// 混合颜色：主体使用顶点颜色(及ColorRect颜色)，描边使用指定颜色
	vec4 final_rgb = mix(vertex_color, outline_color, outline_mask);
	
	// 最终Alpha：主体内部和描边区域可见
	float final_a = (circle_mask + outline_mask) * vertex_color.a;
	
	COLOR = vec4(final_rgb.rgb, final_a);
}