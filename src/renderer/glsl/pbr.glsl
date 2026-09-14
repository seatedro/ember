vec3 pbr_direction(vec3 value) {
    float scale = max(abs(value.x), max(abs(value.y), abs(value.z)));
    if (scale == 0.0) {
        return vec3(0.0);
    }
    return normalize(value / scale);
}

vec3 pbr_brdf(vec3 albedo, float metallic, float roughness, vec3 normal, vec3 view, vec3 direction) {
    float ndotl = max(dot(normal, direction), 0.0);
    float ndotv = max(dot(normal, view), 0.0);
    if (ndotl == 0.0 || ndotv == 0.0) {
        return vec3(0.0);
    }
    vec3 half_direction = normalize(view + direction);
    float ndoth = clamp(dot(normal, half_direction), 0.0, 1.0);
    float vdoth = clamp(dot(view, half_direction), 0.0, 1.0);
    float alpha = roughness * roughness;
    float alpha_squared = alpha * alpha;
    float denominator = (1.0 - ndoth * ndoth) + ndoth * ndoth * alpha_squared;
    float distribution = alpha_squared / (3.141592653589793 * denominator * denominator);
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float geometry = (ndotl / (ndotl * (1.0 - k) + k)) * (ndotv / (ndotv * (1.0 - k) + k));
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 fresnel = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - vdoth, 5.0);
    vec3 diffuse = (1.0 - fresnel) * (1.0 - metallic) * albedo;
    vec3 specular = fresnel * distribution * geometry / max(0.00001, 4.0 * ndotl * ndotv);
    // Cap the specular term to limit extreme highlights from punctual lights.
    return (diffuse + min(specular, vec3(10.0))) * ndotl;
}

vec3 pbr_lighting(vec3 position, vec3 normal, vec3 view_direction, vec3 albedo,
    float metallic, float roughness, float shadow_visibility) {
    normal = normalize(normal);
    vec3 view = pbr_direction(view_direction);
    metallic = clamp(metallic, 0.0, 1.0);
    // A perfectly smooth GGX surface is singular under a punctual light.
    roughness = clamp(roughness, 0.05, 1.0);
    vec3 illumination = ambient.rgb * albedo * (1.0 - metallic);
    for (uint i = 0u; i < point_light_count; ++i) {
        Point_Light light = point_lights[i];
        vec3 to_light = light.position_range.xyz - position;
        vec3 distance_in_ranges = to_light / light.position_range.w;
        float attenuation = max(1.0 - dot(distance_in_ranges, distance_in_ranges), 0.0);
        attenuation *= attenuation;
        vec3 direction = pbr_direction(to_light);
        illumination += pbr_brdf(albedo, metallic, roughness, normal, view, direction)
            * light.color_intensity.rgb * light.color_intensity.w * attenuation;
    }
    for (uint i = 0u; i < directional_light_count; ++i) {
        Directional_Light light = directional_lights[i];
        float visibility = i == shadow_light_index ? shadow_visibility : 1.0;
        illumination += pbr_brdf(albedo, metallic, roughness, normal, view, light.direction.xyz)
            * light.color_intensity.rgb * light.color_intensity.w * visibility;
    }
    return illumination;
}
