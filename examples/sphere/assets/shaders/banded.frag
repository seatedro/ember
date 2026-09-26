#version 450
#extension GL_GOOGLE_include_directive : require
#include "shaders/texture.glsl"
#include "renderer/shaders/lighting.glsl"

layout(location = 0) in vec3 world_position;
layout(location = 2) in vec3 world_normal;
layout(location = 5) in vec3 local_normal;
layout(location = 6) in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(binding = 0) uniform sampler2D albedo_texture;

layout(std140, binding = 2) uniform Material {
    vec4 color_a;
    vec4 color_b;
};

void main() {
    vec3 local = normalize(local_normal);
    float bands = smoothstep(-0.2, 0.2, sin(local.x * 8.0 + local.z * 6.0));
    vec4 albedo = mix(color_a, color_b, bands) * sample_texture(albedo_texture, texture_uv);
    color = vec4(albedo.rgb * diffuse_lighting(world_position, world_normal), albedo.a);
}
