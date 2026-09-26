#version 450
#extension GL_GOOGLE_include_directive : require
#include "shaders/texture.glsl"
#include "lighting.glsl"
#include "shadow.glsl"
#include "pbr.glsl"
#include "environment.glsl"
#include "normal.glsl"

layout(location = 0) in vec3 world_position;
layout(location = 1) in vec3 view_direction;
layout(location = 2) in vec3 world_normal;
layout(location = 3) in vec3 world_tangent;
layout(location = 4) in vec3 world_bitangent;
layout(location = 6) in vec2 texture_uv;
layout(location = 0) out vec4 color;
layout(binding = 0) uniform sampler2D albedo_texture;
layout(binding = 1) uniform sampler2D normal_texture;
layout(binding = 2) uniform sampler2D metallic_texture;
layout(binding = 3) uniform sampler2D roughness_texture;

layout(std140, binding = 2) uniform Material {
    vec4 tint;
    float emission;
    bool use_normal_map;
    float metallic;
    float roughness;
};

void main() {
    vec4 albedo = sample_texture(albedo_texture, texture_uv) * tint;
    vec3 normal = world_normal;
    if (use_normal_map) {
        normal = mapped_normal(world_normal, world_tangent, world_bitangent, sample_texture(normal_texture, texture_uv).rgb);
    }
    float metal = sample_texture(metallic_texture, texture_uv).b * metallic;
    float rough = sample_texture(roughness_texture, texture_uv).g * roughness;
    float visibility = directional_visibility(world_position, world_normal);
    vec3 illumination = pbr_lighting(world_position, normal, view_direction, albedo.rgb, metal, rough, visibility);
    illumination += environment_lighting(normal, view_direction, albedo.rgb, metal, rough, environment);
    color = vec4(illumination + albedo.rgb * emission, albedo.a);
}
