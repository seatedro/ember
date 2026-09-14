float3 environment_direction(float3 d, float angle) {
    float c = cos(angle), s = sin(angle);
    return float3(c*d.x + s*d.z, d.y, -s*d.x + c*d.z);
}
float3 environment_lighting(float3 normal, float3 view, float3 albedo, float metallic, float roughness, float4 settings, texturecube<float> environment_diffuse, sampler environment_diffuse_sampler, texturecube<float> environment_specular, sampler environment_specular_sampler, texture2d<float> environment_brdf, sampler environment_brdf_sampler) {
    if (settings.x == 0.0) return float3(0);
    normal = normalize(normal);
    view = pbr_direction(view);
    metallic = clamp(metallic, 0.0, 1.0);
    roughness = clamp(roughness, 0.05, 1.0);
    float nv = max(dot(normal, view), 0.0);
    float3 f0 = mix(float3(0.04), albedo, metallic);
    float3 f = f0 + (max(float3(1.0 - roughness), f0) - f0) * pow(1.0 - nv, 5.0);
    float3 n = environment_direction(normal, settings.y);
    float3 reflection = environment_direction(reflect(-view, normal), settings.y);
    float3 diffuse = environment_diffuse.sample(environment_diffuse_sampler, n).rgb;
    float3 specular = environment_specular.sample(environment_specular_sampler, reflection, level(roughness * settings.z)).rgb;
    float2 brdf = sample_texture(environment_brdf, environment_brdf_sampler, float2(nv, roughness)).rg;
    return ((1.0 - f) * (1.0 - metallic) * albedo * diffuse + specular * (f0 * brdf.x + brdf.y)) * settings.x;
}
