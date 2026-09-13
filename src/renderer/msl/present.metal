struct Presentation_Uniforms { float exposure; uint tone_mapping; float bloom_strength; uint padding; };

float3 aces_fitted(float3 linear_color) {
    float3x3 input_matrix = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383), float3(0.04823, 0.01566, 0.83777));
    float3x3 output_matrix = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276), float3(-0.07367, -0.00605, 1.07602));
    float3 v = input_matrix * linear_color;
    float3 numerator = v * (v + 0.0245786) - 0.000090537;
    float3 denominator = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(output_matrix * (numerator / denominator), 0.0, 1.0);
}

float3 linear_to_srgb(float3 value) {
    return mix(12.92 * value, 1.055 * pow(value, float3(1.0/2.4)) - 0.055, step(float3(0.0031308), value));
}

fragment float4 present_fragment(Screen_Varyings input [[stage_in]],
    constant Presentation_Uniforms &Material [[buffer(4)]],
    texture2d<float> source_texture [[texture(0)]], sampler source_texture_sampler [[sampler(0)]],
    texture2d<float> bloom_texture [[texture(1)]], sampler bloom_texture_sampler [[sampler(1)]]) {
    float4 source = sample_texture(source_texture, source_texture_sampler, input.texture_uv);
    float3 linear_color = source.rgb;
    if (Material.bloom_strength > 0) {
        linear_color += sample_texture(bloom_texture, bloom_texture_sampler, input.texture_uv).rgb * Material.bloom_strength;
    }

    float3 exposed = max(linear_color, float3(0)) * Material.exposure;
    float3 mapped = Material.tone_mapping == 0 ? exposed / (float3(1) + exposed) : aces_fitted(exposed);
    return float4(linear_to_srgb(mapped), source.a);
}
