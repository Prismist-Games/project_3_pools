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

float sdf_circle(vec2 p, float r) {
    return length(p) - r;
}

void fragment() {
    vec2 uv = UV;
    
    // ========== 采样眼眶纹理 ==========
    vec4 socket_sample = texture(TEXTURE, uv);
    vec4 final_color = socket_sample;
    
    // ========== 眼眶描边 ==========
    if (socket_sample.a > 0.01) {
        float alpha_center = socket_sample.a;
        
        // 使用 fwidth 获取 UV 随屏幕像素的变化率，实现恒定的像素级偏移
        vec2 fw = fwidth(uv);
        // 将 outline_thickness 映射到更有意义的像素范围 (0.04 * 100 = 4 像素)
        vec2 unit_offset = fw * outline_thickness * 100.0;
        
        // 采样周围 4 个点 (或者 8 个点以获得更圆润的效果)
        float alpha_right = texture(TEXTURE, uv + vec2(unit_offset.x, 0.0)).a;
        float alpha_left  = texture(TEXTURE, uv - vec2(unit_offset.x, 0.0)).a;
        float alpha_up    = texture(TEXTURE, uv + vec2(0.0, unit_offset.y)).a;
        float alpha_down  = texture(TEXTURE, uv - vec2(0.0, unit_offset.y)).a;
        
        float alpha_diff = abs(alpha_center - alpha_right) + 
                          abs(alpha_center - alpha_left) + 
                          abs(alpha_center - alpha_up) + 
                          abs(alpha_center - alpha_down);
        
        // 增加 45 度角采样以增强稳定性（可选，如果需要更精致的边框）
        float alpha_ur = texture(TEXTURE, uv + unit_offset * 0.707).a;
        float alpha_dl = texture(TEXTURE, uv - unit_offset * 0.707).a;
        alpha_diff += abs(alpha_center - alpha_ur) + abs(alpha_center - alpha_dl);
        
        if (alpha_diff > 0.1) {
            final_color = outline_color;
        }
        
        // ========== 绘制瞳孔 ==========
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
    
    COLOR = final_color;
}
