struct Lit_Uniforms { float4 tint; float emission; float padding[3]; };

fragment float4 lit_fragment(Mesh_Varyings input [[stage_in]],
    constant Lit_Uniforms &Material [[buffer(4)]],
    constant Lighting_Data &Lighting_Uniforms [[buffer(5)]],
    texture2d<float> albedo_texture [[texture(0)]], sampler albedo_texture_sampler [[sampler(0)]]) {
    float4 albedo = sample_texture(albedo_texture, albedo_texture_sampler, input.texture_uv) * Material.tint;
    return float4(albedo.rgb * (diffuse_lighting(input.world_position, input.world_normal, Lighting_Uniforms) + Material.emission), albedo.a);
}
