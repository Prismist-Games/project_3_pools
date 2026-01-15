shader_type canvas_item;

// 剪影颜色
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// 是否开启剪影效果
uniform bool is_enabled = false;

void fragment() {
    // 获取原始贴图颜色
    vec4 texture_color = texture(TEXTURE, UV);
    
    if (is_enabled) {
        // 【纯色剪影】完全用指定颜色替换，只保留贴图的形状 (Alpha)
        // 不与 COLOR 相乘，确保 ffffff 会渲染成纯白色
        // 但保留节点的整体透明度调制
        float alpha = texture_color.a * COLOR.a;
        COLOR = vec4(silhouette_color.rgb, alpha);
    } else {
        // 正常渲染
        
    }
}
