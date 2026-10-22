layout(binding = 7) uniform sampler2D shadow_texture;

float directional_visibility(vec3 position, vec3 normal) {
    if (shadow_enabled == 0u) {
        return 1.0;
    }
    vec4 clip = shadow_matrix * vec4(position, 1.0);
    vec3 projected = vec3(clip.xy / clip.w * 0.5 + 0.5, clip.z / clip.w);
    if (any(lessThan(projected, vec3(0.0))) || any(greaterThan(projected, vec3(1.0)))) {
        return 1.0;
    }
    vec3 direction = directional_lights[shadow_light_index].direction.xyz;
    float bias = shadow_bias.x + shadow_bias.y * (1.0 - max(dot(normalize(normal), direction), 0.0));
    float depth = sample_texture(shadow_texture, projected.xy).r;
    return projected.z + bias >= depth ? 1.0 : 0.0;
}
