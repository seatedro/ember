#version 450
#extension GL_GOOGLE_include_directive : require
#include "shaders/texture.glsl"

layout(location = 0) in vec2 texture_uv;
layout(location = 1) in vec4 vertex_color;
layout(location = 2) flat in float pixel_range;
layout(binding = 0) uniform sampler2D source_texture;
layout(location = 0) out vec4 color;

float median(vec3 value) {
    return max(min(value.r, value.g), min(max(value.r, value.g), value.b));
}

void main() {
    vec4 sample_color = sample_texture(source_texture, texture_uv);
    if (pixel_range > 0.0) {
        // Convert atlas distances to screen pixels so edges stay crisp at any
        // text size.
        vec2 unit_range = vec2(pixel_range) / vec2(textureSize(source_texture, 0));
        float screen_range = max(0.5 * dot(unit_range, 1.0 / fwidth(texture_uv)), 1.0);
        float coverage = clamp(screen_range * (median(sample_color.rgb) - 0.5) + 0.5, 0.0, 1.0);
        color = vec4(vertex_color.rgb, vertex_color.a * coverage);
    } else {
        color = sample_color * vertex_color;
    }
}
