struct Banded_Uniforms { float4 color_a; float4 color_b; };

fragment float4 banded_fragment(Mesh_Varyings input [[stage_in]],
    constant Banded_Uniforms &Material [[buffer(4)]],
    constant Lighting_Data &Lighting_Uniforms [[buffer(5)]],
    texture2d<float> albedo_texture [[texture(0)]], sampler albedo_texture_sampler [[sampler(0)]]) {
    float3 local = normalize(input.local_normal);
    float bands = smoothstep(-0.2, 0.2, sin(local.x * 8.0 + local.z * 6.0));
    float4 albedo = mix(Material.color_a, Material.color_b, bands) * sample_texture(albedo_texture, albedo_texture_sampler, input.texture_uv);
    return float4(albedo.rgb * diffuse_lighting(input.world_position, input.world_normal, Lighting_Uniforms), albedo.a);
}
