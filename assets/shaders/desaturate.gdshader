shader_type canvas_item;

uniform float saturation;
varying vec4 vertex_color; 

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    COLOR.rgb = mix(vec3(dot(tex_color.rgb, vec3(0.299, 0.587, 0.114))), tex_color.rgb, saturation) * vertex_color.rgb;
	COLOR.a *= vertex_color.a;
}