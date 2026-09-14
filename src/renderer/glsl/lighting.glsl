struct Point_Light {
    vec4 position_range;
    vec4 color_intensity;
};

struct Directional_Light {
    vec4 direction;
    vec4 color_intensity;
};

layout(std140) uniform Lighting_Uniforms {
    vec4 ambient;
    uint point_light_count;
    uint directional_light_count;
    Point_Light point_lights[16];
    Directional_Light directional_lights[4];
    mat4 shadow_matrix;
    vec4 shadow_bias;
    uint shadow_light_index;
    uint shadow_enabled;
    vec4 environment;
};

vec3 diffuse_lighting(vec3 position, vec3 normal, float shadow_visibility) {
    normal = normalize(normal);
    vec3 illumination = ambient.rgb;
    for (uint i = 0u; i < point_light_count; ++i) {
        Point_Light light = point_lights[i];
        vec3 to_light = light.position_range.xyz - position;
        float distance_squared = dot(to_light, to_light);
        float radius = light.position_range.w;
        float attenuation = max(1.0 - distance_squared / (radius * radius), 0.0);
        attenuation *= attenuation;
        // Keep the direction finite when a light coincides with the surface.
        vec3 direction = to_light * inversesqrt(max(distance_squared, 0.000001));
        float diffuse = max(dot(normal, direction), 0.0);
        illumination += light.color_intensity.rgb * light.color_intensity.w * attenuation * diffuse;
    }

    for (uint i = 0u; i < directional_light_count; ++i) {
        Directional_Light light = directional_lights[i];
        float diffuse = max(dot(normal, light.direction.xyz), 0.0);
        float visibility = i == shadow_light_index ? shadow_visibility : 1.0;
        illumination += light.color_intensity.rgb * light.color_intensity.w * diffuse * visibility;
    }

    return illumination;
}

vec3 diffuse_lighting(vec3 position, vec3 normal) {
    return diffuse_lighting(position, normal, 1.0);
}
