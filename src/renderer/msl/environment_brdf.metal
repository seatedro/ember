struct Environment_Filter_Uniforms { uint face; float roughness; uint mode; uint samples; };
fragment float4 environment_fragment(Screen_Varyings input [[stage_in]], constant Environment_Filter_Uniforms &Material [[buffer(4)]]) {
    float2 uv = input.texture_uv;
    uint samples = Material.samples;
    float nv = max(uv.x, 0.0001);
    float roughness = max(uv.y, 0.001);
    float3 v = float3(sqrt(1.0 - nv * nv), 0, nv);
    float2 result = float2(0);
    for (uint i = 0u; i < samples; ++i) {
        float3 h = environment_half(environment_sample(i, samples), roughness);
        float3 l = 2.0 * dot(v, h) * h - v;
        float nl = max(l.z, 0.0);
        float nh = max(h.z, 0.0);
        float vh = max(dot(v, h), 0.0);
        if (nl > 0.0) {
            float k = roughness * roughness * 0.5;
            float g = (nv / (nv * (1.0 - k) + k)) * (nl / (nl * (1.0 - k) + k));
            float visibility = g * vh / max(nh * nv, 0.00001);
            float f = pow(1.0 - vh, 5.0);
            result += float2(1.0 - f, f) * visibility;
        }
    }
    return float4(result / float(samples), 0, 1);
}
