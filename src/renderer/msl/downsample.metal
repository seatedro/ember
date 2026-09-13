struct Downsample_Uniforms { int2 scale; uint2 padding; };

fragment float4 downsample_fragment(Screen_Varyings input [[stage_in]],
    constant Downsample_Uniforms &Material [[buffer(4)]],
    texture2d<float> source_texture [[texture(0)]]) {
    int2 scale = Material.scale;
    int2 size = int2(source_texture.get_width(), source_texture.get_height()) / scale;
    int2 base = clamp(int2(input.texture_uv * float2(size)), int2(0), size - 1) * scale;
    float4 sum = float4(0);
    for (int y = 0; y < scale.y; ++y) {
        for (int x = 0; x < scale.x; ++x) {
            sum += fetch_texture(source_texture, base + int2(x, y));
        }
    }
    return sum / float(scale.x * scale.y);
}
