#version 410 core
in vec3 world_normal;
in vec3 local_normal;
layout(location = 0) out vec4 color;
uniform sampler2D albedo_texture;

layout(std140) uniform Material {
    vec4 color_a;
    vec4 color_b;
};

void main() {
    vec3 normal = normalize(world_normal);
    vec3 light_direction = normalize(vec3(-0.4, 0.8, 0.6));
    float diffuse = max(dot(normal, light_direction), 0.0);

    vec3 local = normalize(local_normal);
    float bands = smoothstep(-0.2, 0.2, sin(local.x * 8.0 + local.z * 6.0));
    vec3 albedo = mix(color_a.rgb, color_b.rgb, bands);
    const float PI = 3.14159265359;
    vec2 uv = vec2(atan(local.z, local.x) / (2.0 * PI) + 0.5,
                   0.5 - asin(clamp(local.y, -1.0, 1.0)) / PI);
    albedo *= texture(albedo_texture, uv).rgb;
    color = vec4(albedo * (0.18 + 0.82 * diffuse), 1.0);
}
