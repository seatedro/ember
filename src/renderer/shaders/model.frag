#version 450
#extension GL_GOOGLE_include_directive : require
#include "shaders/texture.glsl"
#include "lighting.glsl"
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
layout(binding = 0) uniform sampler2D base_color_texture;
layout(binding = 1) uniform sampler2D normal_texture;
layout(binding = 2) uniform sampler2D metallic_roughness_texture;
layout(binding = 3) uniform sampler2D emissive_texture;
layout(binding = 8) uniform sampler2D occlusion_texture;

layout(std140, binding = 2) uniform Material {
    vec4 base_color;
    vec4 emissive;
    float metallic;
    float roughness;
    float alpha_cutoff;
    bool use_normal_map;
};

void main() {
    vec4 albedo = sample_texture(base_color_texture, texture_uv) * base_color;
    if (albedo.a < alpha_cutoff) {
        discard;
    }
    vec3 surface_normal = gl_FrontFacing ? world_normal : -world_normal;
    vec3 normal = surface_normal;
    if (use_normal_map) {
        normal = mapped_normal(surface_normal, world_tangent, world_bitangent, sample_texture(normal_texture, texture_uv).rgb);
    }
    vec4 surface = sample_texture(metallic_roughness_texture, texture_uv);
    float metal = surface.b * metallic;
    float rough = surface.g * roughness;
    float occlusion = sample_texture(occlusion_texture, texture_uv).r;
    vec3 illumination = pbr_lighting(world_position, normal, view_direction, albedo.rgb, metal, rough, 1.0);
    illumination += environment_lighting(normal, view_direction, albedo.rgb, metal, rough, environment) * occlusion;
    illumination += sample_texture(emissive_texture, texture_uv).rgb * emissive.rgb;
    color = vec4(illumination, albedo.a);
}
