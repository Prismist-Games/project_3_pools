shader_type canvas_item;

uniform float scanline_count : hint_range(0, 1800) = 50.0;
uniform float scanline_alpha : hint_range(0, 1) = 0.5;
uniform float scanline_speed : hint_range(-10.0, 10.0) = 1.0;  // New: Speed of scanline movement

uniform float vignette_intensity : hint_range(0, 5) = 0.4;
uniform float screen_curvature : hint_range(0, 0.1) = 0.05;

uniform float jitter_intensity : hint_range(0, 0.1) = 0.0; // New: Jitter amount
uniform float noise_intensity : hint_range(0, 1) = 0.0;     // New: Static noise amount

// Helper function for pseudo-random numbers
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV;
	
	// 1. Screen Curvature / Warp
	// Distort UVs from center
	vec2 center = vec2(0.5, 0.5);
	vec2 offset = uv - center;
	float dist_sq = dot(offset, offset);
	// Basic barrel distortion
	vec2 warped_uv = uv + offset * (dist_sq * screen_curvature);
	
	// If warped UV is outside [0,1], discard or mask (optional, but for overlay we might just want to let it vignette)
	
	// 2. Jitter
	// Offset warped_uv slightly based on time
	float time_step = floor(TIME * 60.0); // Jitter at 60fps intervals
	vec2 jitter_offset = vec2(
		random(vec2(time_step, 1.0)) - 0.5,
		random(vec2(time_step, 2.0)) - 0.5
	) * jitter_intensity;
	
	// Apply jitter to the texture look-up UVs (if we were warping the underlying texture)
	// But since we are an OVERLAY, we aren't distorting the underlying texture directly unless we use SCREEN_TEXTURE.
	// However, this shader is applied to a ColorRect on TOP of content.
	// Standard approach for overlay is to just draw effects over the top.
	// IF we want to distort the underlying text, we would need to use a BackBufferCopy or Screen reading shader.
	// Given the instructions ("add visual effects... to these screens"), and previous setup involving ColorRect overlay:
	// Let's stick to generating effects *on top* that simulate imperfections, 
	// rather than warping the actual game text (which is safer for readability).
	// BUT, "Curvature" usually implies geometric distortion.
	// Since we are just a ColorRect overlay, we can use the curvature to curve the SCANLINES and VIGNETTE.
	
	// Use warped_uv for generating scanlines/vignette to match the curved look
	
	// 3. Scanlines with Roll
	// Use warped_uv.y + TIME for movement
	float scanline = sin((warped_uv.y + TIME * scanline_speed * 0.01) * scanline_count * 3.14159 * 2.0);
	scanline = (scanline + 1.0) * 0.5;
	
	// 4. White Noise
	float noise_val = random(warped_uv + vec2(TIME, TIME));
	
	// 5. Vignette (using warped coords)
	float vig_dist = length(warped_uv - center);
	float vig = smoothstep(0.4, 0.4 + 0.3, vig_dist) * vignette_intensity;

	// Compose Color
	// Start with black
	vec3 dark_color = vec3(0.0);
	
	// Scanlines darken the screen
	float sl_alpha = scanline * scanline_alpha;
	
	// Jitter effect on overlay: random flashes or horizontal offsets?
	// Let's do a horizontal "tearing" scanline occasionall?
	// Or just keep it simple: Jitter shifts the scanlines slightly.
	
	// Update alpha
	float final_alpha = sl_alpha + vig;
	
	// Add noise (whitening)
	vec3 noise_color = vec3(noise_val);
	// Noise adds to color, doesn't just alpha blend black
	
	// Output
	// We mix black overlay (scanlines/vignette) with white noise.
	// This is an overlay, so COLOR.a determines how much we darken/lighten.
	// Darkening: (0,0,0, alpha)
	// Lightening: (1,1,1, alpha)
	// We want mostly darkening, but noise adds light.
	
	COLOR.rgb = noise_color * noise_intensity;
	COLOR.a = clamp(final_alpha + (noise_val * noise_intensity * 0.1), 0.0, 1.0);
}
