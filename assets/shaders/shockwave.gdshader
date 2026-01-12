shader_type canvas_item;

uniform float max_radius : hint_range(0.0, 1.0) = 0.5;
uniform float thickness : hint_range(0.0, 0.5) = 0.05;
uniform float speed : hint_range(0.0, 5.0) = 2.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    float time_val = TIME * speed;
    float dist = distance(UV, vec2(0.5));
    
    // Create multiple repeating waves
    // fract(time - dist) makes it move outwards
    float wave_phase = fract(time_val - dist * 5.0); 
    
    // Only show ring if near the phase wavefront
    // We want exploding rings.
    // Let's rely on Particles2D for the rings actually, as per best practice for "generating" circles.
    // But user asked for "circles generating". A shader can do this by using mod/sin.
    
    float ring = sin(dist * 20.0 - time_val * 10.0);
    float alpha = smoothstep(0.8, 1.0, ring);
    
    // Fade out at edges
    alpha *= smoothstep(0.5, 0.0, dist);
    
    COLOR = color;
    COLOR.a *= alpha;
}
