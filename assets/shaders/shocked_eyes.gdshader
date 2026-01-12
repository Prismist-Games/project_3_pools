shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.9, 0.9, 0.92, 1.0);
uniform vec4 outline_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float outline_thickness : hint_range(0.0, 1.0) = 0.2;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    if (tex_color.a < 0.01) {
        discard;
    }
    
    // UV 坐标通常是归一化的 (0.0-1.0)。
    // 如果 Sprite 的纹理不是正方形，或者 Sprite 的 Scale 不是 1:1，
    // 直接使用 distance(UV, center) 会导致圆形变成椭圆，从而导致描边在长轴方向看起来更细（或相反）。
    
    // 为了修复这个问题，我们需要校正 UV 的纵横比。
    // TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y 告诉我们纹理的高宽比。
    
    vec2 center = vec2(0.5);
    vec2 uv = UV;
    
    // 获取纹理的宽高比
    float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
    
    // 如果纹理是宽的 (aspect < 1.0)，我们缩放 U
    // 如果纹理是高的 (aspect > 1.0)，我们缩放 V
    // 这里我们将 UV 映射到一个以短边为基准的坐标空间，使 "1.0" 代表一个正圆的单位。
    
    if (aspect < 1.0) {
        // 宽图：把 U 压缩
        uv.x = (uv.x - 0.5) / aspect + 0.5;
    } else {
        // 高图：把 V 压缩
        uv.y = (uv.y - 0.5) * aspect + 0.5;
    }
    
    //现在计算距离，就是一个完美的圆了
    float dist = distance(uv, center);
    
    // 基础半径，略小于0.5防止边缘锯齿切断
    // 注意：这里的空间可能被缩放过，如果纹理非常扁，0.5可能会超出边界。
    // 保守起见，取0.48作为 "短边的一半"。
    float radius = 0.48;
    
    float inner_radius = radius - (outline_thickness * 0.5);

    float outer_edge = smoothstep(radius, radius - 0.01, dist);
    float inner_edge = smoothstep(inner_radius, inner_radius - 0.01, dist);
    
    float outline_alpha = outer_edge - inner_edge;
    float fill_alpha = inner_edge;
    
    vec4 final_color = mix(vec4(0.0), outline_color, outline_alpha);
    final_color = mix(final_color, fill_color, fill_alpha);
    
    final_color.a *= tex_color.a;
    
    COLOR = final_color;
}
