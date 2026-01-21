shader_type canvas_item;

// 外描边参数（保持不变）
uniform vec4 line_color : source_color = vec4(1.0);
uniform float width : hint_range(0, 50) = 0.0;
uniform int pattern : hint_range(0, 2) = 0; // diamond, circle, square
uniform bool inside = false;
uniform bool add_margins = true; // only useful when inside is false
uniform vec2 number_of_images = vec2(1.0); // number of horizontal and vertical images in the sprite sheet

// 描线效果参数（替代原置灰功能）
uniform float saturation : hint_range(0, 1) = 1.0;  // 1.0 = 正常显示, 0.0 = 描线模式
uniform bool preview_stroke_mode = false;  // 开关：勾选后强制显示描线效果（方便预览）
uniform vec4 stroke_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);  // 描线颜色（可调整）
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // 填充颜色（可调整）
uniform float stroke_threshold : hint_range(0.0, 1.0) = 0.3;  // 亮度阈值，低于此值视为描线（描边线通常很暗）

varying flat vec4 modulate;

void vertex() {
	modulate = COLOR;
	
	if (add_margins) {
		if ((UV.x <= 0.0 || UV.x >= 1.0) && (UV.y <= 0.0 || UV.y >= 1.0)) {
			VERTEX += (UV * 2.0 - 1.0) * width;
		} else {
			VERTEX += sign(VERTEX) * width;
		}
	}
}

bool hasContraryNeighbour(vec2 uv, vec2 texture_pixel_size, vec2 image_top_left, vec2 image_bottom_right, sampler2D texture) {
	for (float i = -ceil(width); i <= ceil(width); i++) {
		float x = abs(i) > width ? width * sign(i) : i;
		float offset;
		
		if (pattern == 0) {
			offset = width - abs(x);
		} else if (pattern == 1) {
			offset = floor(sqrt(pow(width + 0.5, 2) - x * x));
		} else if (pattern == 2) {
			offset = width;
		}
		
		for (float j = -ceil(offset); j <= ceil(offset); j++) {
			float y = abs(j) > offset ? offset * sign(j) : j;
			vec2 xy = uv + texture_pixel_size * vec2(x, y);
			
			if ((xy != clamp(xy, image_top_left, image_bottom_right) || texture(texture, xy).a <= 0.0) == inside) {
				return true;
			}
		}
	}
	
	return false;
}

void fragment() {
	vec2 uv = UV;
	vec2 image_top_left = floor(uv * number_of_images) / number_of_images;
	vec2 image_bottom_right = image_top_left + vec2(1.0) / number_of_images;
	
	if (add_margins) {
		vec2 texture_pixel_size = vec2(1.0) / (vec2(1.0) / TEXTURE_PIXEL_SIZE + vec2(width * 2.0) * number_of_images);
		
		uv = (uv - texture_pixel_size * width - image_top_left) * TEXTURE_PIXEL_SIZE / texture_pixel_size + image_top_left;
		
		if (uv != clamp(uv, image_top_left, image_bottom_right)) {
			COLOR.a = 0.0;
		} else {
			COLOR = texture(TEXTURE, uv);
		}
	} else {
		COLOR = texture(TEXTURE, uv);
	}
    
    // 1. 描线模式效果（替代原置灰功能）
    // saturation = 1.0 时显示原图，saturation = 0.0 时显示描线+填充效果
    // preview_stroke_mode = true 时强制显示描线效果（用于预览）
    vec4 tex_color = COLOR;
    
    // 计算有效的 saturation 值（预览模式时强制为 0）
    float effective_saturation = preview_stroke_mode ? 0.0 : saturation;
    
    if (effective_saturation < 1.0 && tex_color.a > 0.0) {
        // 计算原始像素的亮度
        float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
        
        // 判断是否为描线区域（深色区域）
        // 描线通常是图片中较暗的部分
        bool is_stroke = luminance < stroke_threshold;
        
        // 根据 saturation 混合：saturation=1 显示原色，saturation=0 显示描线效果
        vec3 stroke_effect;
        if (is_stroke) {
            stroke_effect = stroke_color.rgb;
        } else {
            stroke_effect = fill_color.rgb;
        }
        
        // 使用 effective_saturation 作为混合因子
        COLOR.rgb = mix(stroke_effect, tex_color.rgb, effective_saturation);
    }
    
    COLOR *= modulate;
	
	// 2. 外描边逻辑（保持不变）
	if ((COLOR.a > 0.0) == inside && hasContraryNeighbour(uv, TEXTURE_PIXEL_SIZE, image_top_left, image_bottom_right, TEXTURE)) {
		COLOR.rgb = inside ? mix(COLOR.rgb, line_color.rgb * modulate.rgb, line_color.a * modulate.a) : line_color.rgb;
		COLOR.a += (1.0 - COLOR.a) * line_color.a * modulate.a;
	}
}