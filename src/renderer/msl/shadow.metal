float directional_visibility(float3 position, float3 normal, constant Lighting_Data &lighting,
    depth2d<float> image, sampler state) {
    if (lighting.shadow_enabled == 0) {
        return 1.0;
    }
    float4 clip = lighting.shadow_matrix * float4(position, 1);
    float3 projected = clip.xyz / clip.w * 0.5 + 0.5;
    if (any(projected < float3(0)) || any(projected > float3(1))) {
        return 1.0;
    }
    float3 direction = lighting.directional_lights[lighting.shadow_light_index].direction.xyz;
    float bias = lighting.shadow_bias.x + lighting.shadow_bias.y * (1.0 - max(dot(normalize(normal), direction), 0.0));
    float depth = image.sample(state, float2(projected.x, 1.0 - projected.y));
    return projected.z - bias <= depth ? 1.0 : 0.0;
}
