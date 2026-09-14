struct Environment_Filter_Uniforms { uint face; float roughness; uint mode; uint samples; };
fragment float4 environment_fragment(Screen_Varyings input [[stage_in]], constant Environment_Filter_Uniforms &Material [[buffer(4)]], texturecube<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]]) {
    float2 uv = input.texture_uv;
    uint face = Material.face, mode = Material.mode, samples = Material.samples;
    float roughness = Material.roughness;
    float3 n = cube_direction(face, uv);
    if (mode == 0u) {
        return float4(source_texture.sample(source_texture_sampler, n, level(0.0)).rgb, 1.0);
    }
    float3 up = abs(n.z) < 0.999 ? float3(0,0,1) : float3(1,0,0);
    float3 tangent = normalize(cross(up, n));
    float3 bitangent = cross(n, tangent);
    float3 sum = float3(0);
    float weight = 0.0;
    for (uint i = 0u; i < samples; ++i) {
        float2 u = environment_sample(i, samples);
        float3 l;
        if (mode == 1u) {
            float phi = 6.28318530718 * u.x;
            float radius = sqrt(u.y);
            l = tangent * (radius * cos(phi)) + bitangent * (radius * sin(phi)) + n * sqrt(1.0 - u.y);
        } else {
            float3 h = environment_half(u, roughness);
            h = tangent * h.x + bitangent * h.y + n * h.z;
            l = 2.0 * dot(n, h) * h - n;
        }
        float w = mode == 1u ? 1.0 : max(dot(n, l), 0.0);
        sum += source_texture.sample(source_texture_sampler, l, level(0.0)).rgb * w;
        weight += w;
    }
    return float4(sum / max(weight, 0.00001), 1.0);
}
