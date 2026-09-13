#version 410 core
in vec3 world_position;
in vec3 world_normal;
in vec3 local_normal;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;

layout(std140) uniform Material {
    vec4 color_a;
    vec4 color_b;
};

struct Point_Light {
    vec4 position_range;
    vec4 color_intensity;
};

layout(std140) uniform Lighting_Uniforms {
    vec4 ambient;
    uint point_light_count;
    Point_Light point_lights[16];
};

void main() {
    vec3 normal = normalize(world_normal);
    vec3 illumination = ambient.rgb;
    for (uint i = 0u; i < point_light_count; ++i) {
        Point_Light light = point_lights[i];
        vec3 to_light = light.position_range.xyz - world_position;
        float distance_squared = dot(to_light, to_light);
        float radius = light.position_range.w;
        float attenuation = max(1.0 - distance_squared / (radius * radius), 0.0);
        attenuation *= attenuation;
        // Keep the direction finite when a light coincides with the surface.
        vec3 direction = to_light * inversesqrt(max(distance_squared, 0.000001));
        float diffuse = max(dot(normal, direction), 0.0);
        illumination += light.color_intensity.rgb * light.color_intensity.w * attenuation * diffuse;
    }

    vec3 local = normalize(local_normal);
    float bands = smoothstep(-0.2, 0.2, sin(local.x * 8.0 + local.z * 6.0));
    vec3 albedo = mix(color_a.rgb, color_b.rgb, bands);
    const float PI = 3.14159265359;
    vec2 uv = vec2(atan(local.z, local.x) / (2.0 * PI) + 0.5,
                   0.5 - asin(clamp(local.y, -1.0, 1.0)) / PI);
    albedo *= texture(albedo_texture, uv).rgb;
    color = vec4(albedo * illumination, 1.0);
}
