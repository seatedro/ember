struct Lit_Uniforms { float4 tint; float emission; uint use_normal_map; float padding[2]; };

fragment float4 lit_fragment(Mesh_Varyings input [[stage_in]],
    constant Lit_Uniforms &Material [[buffer(4)]],
    constant Lighting_Data &Lighting_Uniforms [[buffer(5)]],
    texture2d<float> albedo_texture [[texture(0)]], sampler albedo_texture_sampler [[sampler(0)]],
    texture2d<float> normal_texture [[texture(1)]], sampler normal_texture_sampler [[sampler(1)]],
    depth2d<float> shadow_texture [[texture(7)]], sampler shadow_texture_sampler [[sampler(7)]]) {
    float4 albedo = sample_texture(albedo_texture, albedo_texture_sampler, input.texture_uv) * Material.tint;
    float3 normal = input.world_normal;
    if (Material.use_normal_map != 0) {
        normal = mapped_normal(input.world_normal, input.world_tangent, input.world_bitangent, sample_texture(normal_texture, normal_texture_sampler, input.texture_uv).rgb);
    }
    return float4(albedo.rgb * (diffuse_lighting(input.world_position, normal, Lighting_Uniforms, directional_visibility(input.world_position, input.world_normal, Lighting_Uniforms, shadow_texture, shadow_texture_sampler)) + Material.emission), albedo.a);
}
