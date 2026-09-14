struct Sky_Uniforms { float4x4 inverse_view_projection; float4 settings; };
fragment float4 sky_fragment(Screen_Varyings input [[stage_in]], constant Sky_Uniforms &Material [[buffer(4)]], texturecube<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]]) {
    float4 p = Material.inverse_view_projection * float4(input.texture_uv * 2.0 - 1.0, 1.0, 1.0);
    float3 d = normalize(p.xyz / p.w);
    float c = cos(Material.settings.y), s = sin(Material.settings.y);
    d = float3(c*d.x + s*d.z, d.y, -s*d.x + c*d.z);
    return float4(source_texture.sample(source_texture_sampler, d, level(0.0)).rgb * Material.settings.x, 1.0);
}
