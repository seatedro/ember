struct Lit_Uniforms { float4 tint; float emission; uint use_normal_map; float metallic; float roughness; };

fragment float4 lit_fragment(Mesh_Varyings input [[stage_in]],
    constant Lit_Uniforms &Material [[buffer(4)]],
    constant Lighting_Data &Lighting_Uniforms [[buffer(5)]],
    texture2d<float> albedo_texture [[texture(0)]], sampler albedo_texture_sampler [[sampler(0)]],
    texture2d<float> normal_texture [[texture(1)]], sampler normal_texture_sampler [[sampler(1)]],
    texture2d<float> metallic_texture [[texture(2)]], sampler metallic_texture_sampler [[sampler(2)]],
    texture2d<float> roughness_texture [[texture(3)]], sampler roughness_texture_sampler [[sampler(3)]],
    depth2d<float> shadow_texture [[texture(7)]], sampler shadow_texture_sampler [[sampler(7)]]) {
    float4 albedo = sample_texture(albedo_texture, albedo_texture_sampler, input.texture_uv) * Material.tint;
    float3 normal = input.world_normal;
    if (Material.use_normal_map != 0) {
        normal = mapped_normal(input.world_normal, input.world_tangent, input.world_bitangent, sample_texture(normal_texture, normal_texture_sampler, input.texture_uv).rgb);
    }
    float metallic = sample_texture(metallic_texture, metallic_texture_sampler, input.texture_uv).b * Material.metallic;
    float roughness = sample_texture(roughness_texture, roughness_texture_sampler, input.texture_uv).g * Material.roughness;
    float visibility = directional_visibility(input.world_position, input.world_normal, Lighting_Uniforms, shadow_texture, shadow_texture_sampler);
    float3 illumination = pbr_lighting(input.world_position, normal, input.view_direction, albedo.rgb, metallic, roughness, Lighting_Uniforms, visibility);
    return float4(illumination + albedo.rgb * Material.emission, albedo.a);
}
