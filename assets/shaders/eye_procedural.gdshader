shader_type canvas_item;

// 眼眶描边
uniform vec4 outline_color : source_color = vec4(1.0, 0.44, 0.35, 1.0);
uniform float outline_thickness : hint_range(0.001, 0.2) = 0.04;

// 瞳孔
uniform sampler2D pupil_texture : hint_default_black;
uniform bool use_pupil_texture = false;
uniform vec2 pupil_offset = vec2(0.0, 0.0);
uniform float pupil_scale : hint_range(0.0, 2.0) = 1.0; // 0.0 隐藏瞳孔
uniform vec4 pupil_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // 纯色模式或纹理着色
uniform vec4 pupil_outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float pupil_outline_thickness : hint_range(0.0, 0.1) = 0.0;
varying vec4 vertex_color; 

void vertex() {
	vertex_color = COLOR;
}

float sdf_circle(vec2 p, float r) {
    return length(p) - r;
}

void fragment() {
    vec2 uv = UV;
    
    // ========== 采样眼眶纹理 ==========
    vec4 socket_sample = texture(TEXTURE, uv);
    vec4 final_color = socket_sample;
    
    // ========== 眼眶描边 ==========
    // 允许向外描边，修复因内缩导致的白边问题
    {
        float alpha_center = socket_sample.a;
        
        // 使用 TEXTURE_PIXEL_SIZE 替代 fwidth，使描边宽度相对于纹理固定
        // 这样可以防止描边随屏幕分辨率或缩放而改变粗细
        vec2 unit_offset = TEXTURE_PIXEL_SIZE * outline_thickness * 100.0;
        
        vec2 uv_right = uv + vec2(unit_offset.x, 0.0);
        vec2 uv_left  = uv - vec2(unit_offset.x, 0.0);
        vec2 uv_up    = uv + vec2(0.0, unit_offset.y);
        vec2 uv_down  = uv - vec2(0.0, unit_offset.y);
        
        // 边界检查：超出 [0,1] 范围的采样视为透明
        float alpha_right = (uv_right.x >= 0.0 && uv_right.x <= 1.0) ? texture(TEXTURE, uv_right).a : 0.0;
        float alpha_left  = (uv_left.x >= 0.0 && uv_left.x <= 1.0) ? texture(TEXTURE, uv_left).a : 0.0;
        float alpha_up    = (uv_up.y >= 0.0 && uv_up.y <= 1.0) ? texture(TEXTURE, uv_up).a : 0.0;
        float alpha_down  = (uv_down.y >= 0.0 && uv_down.y <= 1.0) ? texture(TEXTURE, uv_down).a : 0.0;
        
        float alpha_diff = abs(alpha_center - alpha_right) + 
                          abs(alpha_center - alpha_left) + 
                          abs(alpha_center - alpha_up) + 
                          abs(alpha_center - alpha_down);
        
        vec2 uv_ur = uv + unit_offset * 0.707;
        vec2 uv_dl = uv - unit_offset * 0.707;
        float alpha_ur = (uv_ur.x >= 0.0 && uv_ur.x <= 1.0 && uv_ur.y >= 0.0 && uv_ur.y <= 1.0) ? texture(TEXTURE, uv_ur).a : 0.0;
        float alpha_dl = (uv_dl.x >= 0.0 && uv_dl.x <= 1.0 && uv_dl.y >= 0.0 && uv_dl.y <= 1.0) ? texture(TEXTURE, uv_dl).a : 0.0;
        alpha_diff += abs(alpha_center - alpha_ur) + abs(alpha_center - alpha_dl);
        
        float outline_factor = smoothstep(0.001, 0.05, alpha_diff);
        
        if (outline_factor > 0.0) {
            // 如果是在原本透明的区域（外部描边），直接使用描边颜色
            if (alpha_center < 0.01) {
                final_color.rgb = outline_color.rgb;
            } else {
                final_color.rgb = mix(final_color.rgb, outline_color.rgb, outline_factor);
            }
            // 增强 Alpha 以显示外部描边
            final_color.a = max(final_color.a, outline_factor * outline_color.a);
        }
    }
        
    // ========== 绘制瞳孔 ==========
    // 限制瞳孔在原眼眶范围内（避免溢出到外部描边区域或纹理外）
    if (socket_sample.a > 0.01) {
        if (pupil_scale > 0.001) {
            vec2 pupil_center = vec2(0.5) + pupil_offset * 0.2;
            vec2 pupil_uv_centered = (uv - pupil_center) / pupil_scale;
            vec2 pupil_tex_uv = pupil_uv_centered + vec2(0.5);
            
            vec4 pupil_sample = vec4(0.0);
            float pupil_mask = 0.0;
            
            if (use_pupil_texture) {
                // ========== 纹理模式 ==========
                if (pupil_tex_uv.x >= 0.0 && pupil_tex_uv.x <= 1.0 && 
                    pupil_tex_uv.y >= 0.0 && pupil_tex_uv.y <= 1.0) {
                    vec4 tex_sample = texture(pupil_texture, pupil_tex_uv);
                    pupil_mask = tex_sample.a;
                    
                    // 对纹理应用颜色着色
                    pupil_sample = vec4(tex_sample.rgb * pupil_color.rgb, tex_sample.a);
                    
                    // 瞳孔纹理描边：不受缩放影响
                    if (pupil_outline_thickness > 0.001 && tex_sample.a > 0.01) {
                        // 使用瞳孔 UV 的像素变化率
                        vec2 p_fw = fwidth(pupil_tex_uv);
                        vec2 p_offset = p_fw * pupil_outline_thickness * 100.0;
                        
                        float p_alpha_c = tex_sample.a;
                        float p_alpha_r = texture(pupil_texture, pupil_tex_uv + vec2(p_offset.x, 0.0)).a;
                        float p_alpha_l = texture(pupil_texture, pupil_tex_uv - vec2(p_offset.x, 0.0)).a;
                        float p_alpha_u = texture(pupil_texture, pupil_tex_uv + vec2(0.0, p_offset.y)).a;
                        float p_alpha_d = texture(pupil_texture, pupil_tex_uv - vec2(0.0, p_offset.y)).a;
                        
                        float p_diff = abs(p_alpha_c - p_alpha_r) + abs(p_alpha_c - p_alpha_l) +
                                       abs(p_alpha_c - p_alpha_u) + abs(p_alpha_c - p_alpha_d);
                        
                        if (p_diff > 0.1) {
                            pupil_sample = pupil_outline_color;
                        }
                    }
                }
            } else {
                // ========== 程序化圆形模式 ==========
                float pupil_radius = 0.3;
                float pupil_dist = sdf_circle(pupil_uv_centered, pupil_radius);
                
                // 使用 fwidth(pupil_dist) 实现亚像素级抗锯齿，边缘宽度恒定为一个像素
                float pixel_dist = fwidth(pupil_dist);
                pupil_mask = smoothstep(pixel_dist, -pixel_dist, pupil_dist);
                
                if (pupil_mask > 0.01) {
                    pupil_sample = pupil_color;
                    
                    // 程序化描边：不受缩放影响
                    if (pupil_outline_thickness > 0.001) {
                        // 偏移值根据屏幕像素距离计算
                        float thickness_uv = pixel_dist * pupil_outline_thickness * 100.0;
                        float outline_dist = pupil_dist + thickness_uv;
                        float outline_mask = smoothstep(pixel_dist, -pixel_dist, outline_dist);
                        
                        if (outline_mask > pupil_mask) {
                            pupil_sample = pupil_outline_color;
                            pupil_mask = outline_mask;
                        }
                    }
                    
                    // 高光 (保持相对于瞳孔的大小)
                    vec2 highlight_pos = pupil_uv_centered - vec2(-0.1, -0.1);
                    float highlight_dist = sdf_circle(highlight_pos, pupil_radius * 0.35);
                    float highlight_mask = smoothstep(pixel_dist, -pixel_dist, highlight_dist);
                    if (highlight_mask > 0.1) {
                        pupil_sample = mix(pupil_sample, vec4(1.0, 1.0, 1.0, 1.0), highlight_mask * 0.7);
                    }
                }
            }
            
            // 合成瞳孔
            final_color = mix(final_color, pupil_sample, pupil_mask);
        }
    }
    
    COLOR = final_color * vertex_color;
}
